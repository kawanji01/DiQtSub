class Lang < ApplicationRecord
  # GoogleTranslationAPIや言語関係の便利メソッドをまとめたもの
  # 絶対もっと良いやり方があるはずだけど、わからないのでとりあえずモデルで対処した。
  # このモデルは手動で作成したので、migrationファイルなどは作成されていない。
  # こうしたモデルをサービスクラスと呼ぶらしい。
  # そしてサービスクラスとしては、このようないくつもパブリックなメソッドを集めた実装はよくないらしいので、
  # servicable.rbとsanitizer.rbを参考に、「スタティックファクトリーメソッドパターン」に直したい。
  # TODO： Google翻訳とDeepL翻訳の処理は、translator.rb として独立したサービスクラスに切り分ける。

  # 言語コードを言語番号に変換して返す / convert lang_code into lang_number and return lang_number
  # 言語コードを言語番号に変換する処理は、すべて必ずこのメソッドを使うこと！ / You have to use it in all processes to convert lang_code to lang_number.
  def self.convert_code_to_number(lang_code)
    hash = Languages::CODE_MAP.find { |k, v| k == lang_code }
    return if hash.blank?

    hash.second
  end

  # 言語番号を言語コードに変換して返す / convert lang_number into lang_code and return lang_code
  # 言語番号を言語コードに変換する処理は、すべて必ずこのメソッドを使うこと！ / You have to use it in all processes to convert lang_number to code..
  def self.convert_number_to_code(number)
    hash = Languages::CODE_MAP.find { |k, v| v == number }
    return if hash.blank?

    hash.first
  end


  # "en-j3PyPqV-e1s"とか"zh-Hans-419"といった値（主に手動字幕で用いられる）を、DiQtで扱えるlang_codeに変換する。
  def self.convert_value_to_code(value)
    lang_code = nil
    if Lang.lang_code_supported?(value)
      # 一度言語コードを番号に変換してからコードに再変換することで、DiQt の対応している言語コードに変換する。
      lang_number = Lang.convert_code_to_number(value)
      lang_code = Lang.convert_number_to_code(lang_number)
    elsif Lang.lang_code_supported?(value.sub('auto-', ''))
      lang_code = value.sub('auto-', '')
    elsif Lang.lang_code_supported?(value.sub(/-.*/, ''))
      #  "en-j3PyPqV-e1s" のような言語コードがあった場合に、enとして扱う。問題が起きた動画: https://www.youtube.com/watch?v=cyFM2emjbQ8&list=PLjxrf2q8roU3wk7CDw4RfV3mEwOJbjx1k&index=7
      code = value.sub(/-.*/, '')
      lang_number = Lang.convert_code_to_number(code)
      lang_code = Lang.convert_number_to_code(lang_number)
    elsif Lang.lang_code_supported?(value.match(/^[^-]+-[^-]+/)[0])
      # "zh-Hans-419" のような言語コードがあった場合に、zh-Hans として扱う。
      code = value.match(/^[^-]+-[^-]+/)[0]
      lang_number = Lang.convert_code_to_number(code)
      lang_code = Lang.convert_number_to_code(lang_number)
    end
    lang_code
  end



  # 引数のテキストの言語コードを返す
  def self.return_lang_data(text)
    url = URI.parse('https://translation.googleapis.com/language/translate/v2/detect')
    params = {
      q: text,
      key: ENV['GOOGLE_CLOUD_API_KEY']
    }
    url.query = URI.encode_www_form(params)
    res = Net::HTTP.get_response(url)
    json = res.body
    # レスポンスのjsonの言語のパラメータをパースする
    JSON.parse(json)['data']['detections'][0][0]['language']
  end

  # 引数のテキストの言語が何であるか、DiQt全体で統一している言語番号で返す。
  def self.return_lang_number(text)
    convert_code_to_number return_lang_data(text)
  end

  # BooQsでサポートされている言語コードか？
  def self.lang_code_supported?(lang_code)
    convert_code_to_number(lang_code).present?
  end

  # BooQsでサポートされていない言語コードか？
  def self.lang_code_unsupported?(lang_code)
    !lang_code_supported?(lang_code)
  end

  # ある言語番号が分かち書きするべきかを判別する
  def self.text_to_be_separated?(lang_number)
    # 中国語（簡体・繁体/14・15）・日本語（44）・韓国語（50）なら、分かち書きできる。
    [14, 15, 44, 50].include?(lang_number)
  end

  # 言語コードを引数に、該当するBCP47の言語コードの一覧を取得する。
  # BCP47はspeech-to-textのlanguage_codeとして渡す必要がある。
  def self.find_all_bcp47(lang_code)
    array = Languages::BCP47_MAP.find_all { |k, v| v == lang_code }
    return if array.blank?

    array.map { |a| a[0] }
  end

  # BCP47を言語コードに変換する
  def self.convert_bcp47_to_code(bcp47)
    hash = Languages::BCP47_MAP.find { |k, v| k == bcp47 }
    return if hash.blank?

    hash.second
  end

  # BCP47を言語番号に変換する
  def self.convert_bcp47_to_number(bcp47)
    code = Lang.convert_bcp47_to_code(bcp47)
    Lang.convert_code_to_number(code)
  end

  # google翻訳
  def self.google_translate(source, target, context)
    # sourceとtargetが同じ言語なら翻訳できないのでリターン。
    return if source == target

    url = URI.parse('https://www.googleapis.com/language/translate/v2')
    params = {
      q: context,
      target: target, # 翻訳結果の言語
      source: source, # 翻訳元の言語の種類
      key: ENV['GOOGLE_CLOUD_API_KEY']
    }
    url.query = URI.encode_www_form(params)
    res = Net::HTTP.get_response(url)
    json = res.body
    # レスポンスのjsonの言語の翻訳結果の部分のパラメータをパースする
    JSON.parse(json)['data']['translations'].first['translatedText'] rescue puts "failed: #{source} / #{target} / #{context}"
  end

  # DeepLで翻訳する
  def self.deepl_translate(source, target, context)
    translation = DeepL.translate context, source, target
    translation.text
  end

  # DeepLの対応している言語コードを取得する
  def self.deepl_supported_languages
    DeepL.languages.map { |language| language.code.downcase }
  end


  # テキストの分かち書き処理
  def self.separate_text(text, lang_number)
    syntax_response = Lang.analyze_syntax(text, lang_number)
    return if syntax_response.blank?

    # AnalysisSyntaxResponse / https://googleapis.dev/ruby/google-cloud-language-v1/latest/Google/Cloud/Language/V1/AnalyzeSyntaxResponse.html
    # Token / https://googleapis.dev/ruby/google-cloud-language-v1/latest/Google/Cloud/Language/V1/Token.html
    syntax_response.tokens.map { |t| t.text.content }.join(' ')
  end

  # 構文解析
  # Gem / https://github.com/googleapis/google-cloud-ruby/tree/master/google-cloud-language
  # API Document / https://googleapis.dev/ruby/google-cloud-language/v1.3.0/file.AUTHENTICATION.html#environment-variables
  def self.analyze_syntax(text, lang_number)
    language = case lang_number
               when 44
                 'ja'
               when 14
                 'zh'
               when 15
                 # zh-TWではないことに注意
                 'zh-Hant'
               when 50
                 'ko'
               end

    return if language.blank? || text.blank?

    # Authentication / https://googleapis.dev/ruby/google-cloud-language/latest/file.AUTHENTICATION.html
    # client = Google::Cloud::Language.language_service
    client = Google::Cloud::Language.language_service do |config|
      # JSONデータを環境変数に格納し、config.credentialsというrubyのコードに渡すときに、JSONをRubyにparseしてから渡す。
      config.credentials = JSON.parse(ENV['GOOGLE_CREDENTIALS'])
    end

    # スクレイピングしてきたhtmlでutf-8にない文字コードがあった場合、分かち書き実行時にEncoding::UndefinedConversionErrorが起きる。解決方法：　https://blog.tanebox.com/archives/452/
    encoded_text = text.force_encoding('UTF-8')
    # Document / https://googleapis.dev/ruby/google-cloud-language-v1/latest/Google/Cloud/Language/V1/Document.html
    # 対応言語一覧 / https://cloud.google.com/natural-language/docs/languages
    document = { content: encoded_text,
                 type: :PLAIN_TEXT,
                 language: language }
    # analysis_syntax / https://googleapis.dev/ruby/google-cloud-language-v1/latest/Google/Cloud/Language/V1/AnalyzeSyntaxRequest.html
    syntax_response = client.analyze_syntax(
      document: document
    )
    syntax_response
  end


end

