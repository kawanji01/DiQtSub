module ApplicationHelper

  def default_meta_tags
    {
      site: 'BooQs Sub',
      title: 'Youtubeの字幕をダウンロード',
      reverse: true,
      charset: 'utf-8',
      description: 'Youtubeの字幕をダウンロードできます！',
      keywords: 'Youtube, 字幕, Subtitle, Caption',
      canonical: request.original_url,
      separator: '|',
      icon: [
        { href: image_url('favicon/favicon-32x32.png') },
        { href: image_url('BooQs_icon.png'), rel: 'apple-touch-icon', sizes: '180x180', type: 'image/jpg' },
      ],
      og: {
        site_name: :site, # もしくは site_name: :site
        title: :title, # もしくは title: :title
        description: :description, # もしくは description: :description
        type: 'website',
        url: request.original_url,
        image: image_url('OGP_BooQs.png'),
        locale: 'ja_JP',
      },
      twitter: {
        card: 'summary',
        site: '@BooQs_net'
      }
    }
  end





  # Youtubeの動画のidを返す / Return Youtube's movie ID
  def return_youtube_id(url)
    Youtube.get_video_id(url)
  end

  # 引数の秒数を、シークバーの再生時間と同じフォーマットの文字列に変換して返す。
  def return_play_time(time)
    hours = time.to_i / 3600
    minutes = time.to_i / 60
    # 分数を01のようにする。
    minutes = '0' + minutes.to_s if minutes < 10
    seconds = (time.to_i % 60).round(3)
    # 1.0のような表現を防ぐ。
    seconds = seconds.to_i if seconds.to_s.split('.').second == '0'
    # 秒数を01のようにする
    seconds = '0' + seconds.to_s if seconds < 10

    if hours.zero?
      "#{minutes}:#{seconds}"
    else
      "#{hours}:#{minutes}:#{seconds}"
    end
  end

  # 引数の秒数を、srtファイルの再生時間と同じフォーマットの文字列に変換して返す
  def return_play_time_for_srt(time)
    return "0" if time.blank?
    hours = time.to_i / 3600
    minutes = time.to_i / 60
    # 分数を01のようにする。
    minutes = '0' + minutes.to_s if minutes < 10
    hours = '0' + hours.to_s if hours < 10
    seconds = (time % 60).round(3)

    if seconds < 10
      "#{hours}:#{minutes}:0#{seconds.to_i},000"
    else
      "#{hours}:#{minutes}:#{seconds.to_i},000"
    end
  end

  # 開始時間から終了時間までを文字列で返す。
  def return_play_time_from_start_to_end(start_time, end_time)
    "#{return_play_time(start_time)} ~ #{return_play_time(end_time)}"
  end

end
