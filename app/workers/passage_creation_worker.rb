class PassageCreationWorker
  include Sidekiq::Worker
  sidekiq_options queue: :often

  # transcript_typeは'auto-generated'かlang_code（enやjaなど）のどちらか。
  def perform(article_uid, transcript_type, lang_code, locale, user_id)
    p 'passage creation'
    article = Article.find_param(article_uid)
    file_name = "transcript-#{transcript_type}_#{article_uid}"
    lang_number = Lang.convert_code_to_number(lang_code)
    # passageに取り込むためのCSVを作成する。
    is_auto = transcript_type == 'auto-generated'
    # 字幕のSRTをダウンロードする。
    file, error = Youtube.download_sub_srt(file_name, article.reference_url, lang_code, is_auto)
    p error if error.present?
    return if error.present?

    # SRTをpassageに取り込めるようにCSVに変換する。その際、SRTの重複表現を消す。
    csv = Youtube.convert_srt_into_csv(file, lang_number, true)
    return if csv.blank?

    # CSVをs3にアップロードして、ファイルのpathを手に入れる。
    # file_name_csv = "#{file_name}.csv"
    # uploaded_file_url = FileUtility.upload_file_and_get_s3_path(csv, file_name_csv)

    # CSV.parseについて。https://docs.ruby-lang.org/ja/latest/method/CSV/s/parse.html
    # S3のCSVを開く方法 https://qiita.com/ironsand/items/0211ad6773d22cbc1263
    # passages_csv = CSV.parse(open(uploaded_file_url).read, headers: true)
    passages_csv = CSV.parse(csv, headers: true)
    passages_count = passages_csv.length
    passages_csv.each_with_index do |row, i|
      # htmlタグ＆末尾の不要な改行を取り除く。
      #text = Sanitize.clean(row['text']).strip
      sanitizer = Sanitizer.call(row['text'])
      text = sanitizer.text
      # CSVにlang_numberが設定されているならそれを採用し、設定されていないならテキストから言語を調査して設定する。
      lang_number = row['lang_number'] if lang_number.blank?
      lang_number = Lang.return_lang_number(text) if lang_number.blank?
      lang_number = article.lang_number if lang_number.blank?
      next if text.blank?

      article.passages.build(text: text.strip,
                             lang_number: lang_number,
                             start_time: row['start_time'].to_d,
                             start_time_minutes: row['start_time_minutes'].to_i,
                             start_time_seconds: row['start_time_seconds'].to_d,
                             end_time: row['end_time'].to_d,
                             end_time_minutes: row['end_time_minutes'].to_i,
                             end_time_seconds: row['end_time_seconds'].to_d)

      ActionCable.server.broadcast 'progress_bar_channel',
                                   content_id: article_uid,
                                   user_id: user_id,
                                   all_count: passages_count,
                                   process_count: i,
                                   redirect_url: "/#{locale}/articles/#{article_uid}"
    end

    if article.save && Rails.env.production?
      # 使い終わったCSVをS３から消す
      # FileUtility.delete_s3_tmp_file(file_name_csv)
      Open3.capture3("rm tmp/#{file_name}*")
    else
      Open3.capture3("rm tmp/#{file_name}*")
    end

    ActionCable.server.broadcast 'progress_bar_channel',
                                 content_id: article_uid,
                                 user_id: user_id,
                                 all_count: passages_count,
                                 process_count: passages_count,
                                 redirect_url: "/#{locale}/articles/#{article_uid}"
  end
end

# Translation_creation_workerと同じく、日本語の文字化けの解決ができなかったので、S3に一度アップロードするのはやめた。
# 考えてみれば、わざわざ一度アップロードする必要はない。