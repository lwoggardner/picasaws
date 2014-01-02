PicasaWS::Config.configure do

    album {{
        id: dir.basename,
        title: dir.basename,
        comment: nil,
        timestamp: dir.mtime
    }}

    photo {{
        id: file.basename(".*"),
        caption: nil,
        keywords: nil,
        timestamp:  file.mtime
    }}

    photo("image/jpeg") {{
        caption: join(
            xmp.dc.title,
            exif.document_name,
            xmp.photoshop.Headline,
            exif.comment,
            exif.user_comment,
            exif.image_description,
            "\n"
    ),
        keywords: (xmp.dc.subject || xmp.digiKam.TagsList),
        timestamp: (exif.date_time_original || file.mtime)
    }}

    photo("image/tiff") {{
        caption: join(
            exif.document_name,
            exif.image_description,
            exif.user_comment,
            "\n")
    }}

    #video {{
    #    id: (nil unless ffmpeg.duration < 15.minutes)
    #}}

    transform("image/jpeg","image/tiff") do 
        rmagick_resize()
    end
end
