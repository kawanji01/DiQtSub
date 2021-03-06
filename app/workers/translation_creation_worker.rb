# Youtubeの字幕を翻訳として読み込むWorker
class TranslationCreationWorker
  include Sidekiq::Worker
  sidekiq_options queue: :often

  # lang_valueは、yt-dlp で　--sub-lang として指定する値。
  # 自動字幕なら"en" のような普通のlang_codeだが、
  # 手動字幕だと場合によっては "en-j3PyPqV-e1s" のような不規則な値が設定されている。
  def perform(article_uid, translation_type, lang_value, locale, user_uid)
    article = Article.find_param(article_uid)
    lang_code = Lang.convert_value_to_code(lang_value)
    lang_number = Lang.convert_code_to_number(lang_code)
    # タイトルに指定の言語の翻訳がついておらず、かつ、タイトルの言語と翻訳の言語が異なるなら、YouTubeからタイトルの翻訳も取得する。
    if article.find_title_translation(lang_number).blank? && article.lang_number != lang_number
      translated_title = Youtube.get_translated_title(article.reference_url, lang_code)
      # return ifの早期リターンで抜けようとするとsidekiqの処理そのものが終了してしまったので、ifをネストした。
      if translated_title.present?
        article.title_translation_new(lang_number, translated_title)
        # translation_of_title = article.title_translation_new(lang_number, translated_title)
        # translation_of_title.separate_text
      end
    end

    file_name = "translation-#{translation_type}_#{article_uid}_#{user_uid}"

    # translationに取り込むためのCSVを作成する。
    is_auto = translation_type == 'auto-generated'
    # 字幕のSRTをダウンロードする。
    # ダウンロードでは、lang_code（en）ではなく、lang_value（en-j3PyPqV-e1s）を引数に渡す。
    file, error = Youtube.download_sub_srt(file_name, article.reference_url, lang_value, is_auto)
    return p error if error.present?

    # SRTをpassageに取り込めるようにCSVに変換する。その際、SRTの重複表現を消す。
    csv = Youtube.convert_srt_into_csv(file, lang_number, true)
    return p 'CSV blank' if csv.blank?

    file_name_csv = "translation-#{lang_code}_#{article_uid}_#{user_uid}.csv"
    # URL経由で読み込むと文字化けする。 row['text'].force_encoding("UTF-8") をしても途中で処理が止まる。
    # uploaded_file_url = FileUtility.upload_file_and_get_s3_path(csv, file_name_csv)

    # CSV.parseについて。https://docs.ruby-lang.org/ja/latest/method/CSV/s/parse.html
    # S3のCSVを開く方法 https://qiita.com/ironsand/items/0211ad6773d22cbc1263
    # translations_csv = CSV.parse(open(uploaded_file_url).read, headers: true)
    translations_csv = CSV.parse(csv, headers: true)
    translations_count = translations_csv.length
    translations_csv.each_with_index do |row, i|
      # SlackNotificationWorker.perform_async('#webhook-test', "encode error", "#{row['text'].force_encoding("UTF-8")}", "row[text]") if i % 20 == 0 && row['text'].present?
      # text_utf8 = row['text'].force_encoding("UTF-8")
      # htmlタグや末尾の不要な改行を取り除く。
      sanitizer = Sanitizer.call(row['text'])
      text = sanitizer.text
      next if text.blank?

      start_time = row['start_time'].to_d
      end_time = row['end_time'].to_d

      # start_timeとend_timeの平均から、翻訳の参照元のpassageを決定する。
      average_time = (start_time + end_time) * 0.5
      # passage = article.passages.find { |p| p.start_time.to_d <= average_time && p.end_time.to_d >= average_time }
      # passage = article.passages.order(start_time: :asc).find { |p|  p.end_time.to_d >= average_time }
      # 上の二つの処理ではうまく翻訳の字幕がpassageに対応できなかった。上の処理だと翻訳の読み込みに失敗する動画 ref: https://www.youtube.com/watch?v=_M-6lkoi6L4
      passage = article.passages.order(start_time: :desc).find { |p| p.start_time.to_d <= average_time }
      next if passage.blank?
      # passageと同じ言語の翻訳は作らない。
      next if passage.lang_number == lang_number

      # whereではなくfindで検索しているのは、前回のイテレーションでsaveしたtranslationも確実に検索結果に含めるため。
      if (translation = passage.translations&.find { |t| t&.lang_number == lang_number })
        # 参照元候補のpassageに、対象言語の翻訳がすでについているなら、参照元候補のpassageの翻訳に、翻訳をマージする。
        text = [translation.text, text].join("\n")
        translation.text = text.strip
      else
        translation = passage.translations.build(article_id: article.id,
                                                 text: text,
                                                 lang_number: lang_number)
      end
      translation.save
      p translation.text

      # translation.separate_text
      ActionCable.server.broadcast 'progress_bar_channel',
                                   content_id: article_uid,
                                   user_id: user_uid,
                                   all_count: translations_count,
                                   process_count: i,
                                   redirect_url: "/#{locale}/articles/#{article_uid}?sub=#{lang_code}"
    end

    if article.save && Rails.env.production?
      # 使い終わったCSVをS3から消す
      #FileUtility.delete_s3_tmp_file(file_name_csv)
      Open3.capture3("rm tmp/#{file_name_csv}")
    else
      Open3.capture3("rm tmp/#{file_name_csv}")
    end
    ActionCable.server.broadcast 'progress_bar_channel',
                                 content_id: article_uid,
                                 user_id: user_uid,
                                 all_count: translations_count,
                                 process_count: translations_count,
                                 redirect_url: "/#{locale}/articles/#{article_uid}?sub=#{lang_code}"
  end
end
