import SwiftUI

struct ImagePreviewRow: View {
    let attachments: [ImageAttachment]
    let onDelete: (ImageAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    PreviewImageThumbnail(
                        attachment: attachment,
                        onDelete: {
                            onDelete(attachment)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.chatBackground)
    }
}