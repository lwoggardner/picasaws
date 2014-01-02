PicasaWS::Config.configure do

    album {{
        id: xattr['user.shotwell.event_id'],
        title: dir.basename,
        comment: xattr['user.shotwell.event_comment'],
        timestamp: dir.mtime
    }}

    photo {{
        id: xattr['user.shotwell.transform_id'],
        caption: join(xattr['user.shotwell.title'],xattr['user.shotwell.comment'],"\n"),
        keywords: xattr["user.shotwell.keywords"],
        timestamp: file.mtime
    }}
    
    video {{
        id: (file.size < 104857600) ? "v:#{xattr['user.shotwell.transform_id']}" : nil,
        caption: join(xattr['user.shotwell.title'],xattr['user.shotwell.comment'],"\n"),
        keywords: xattr["user.shotwell.keywords"],
        timestamp: file.mtime
    }}

end
