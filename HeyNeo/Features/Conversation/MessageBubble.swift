import SwiftUI

/// A chat message bubble
struct MessageBubble: View {
    let message: Message
    
    private var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(isUser ? .white : .primary)
                    .textSelection(.enabled)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            Color.blue
        } else {
            Color(.systemGray5)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(message: Message(
            role: .user,
            content: "What's the weather like today?"
        ))
        
        MessageBubble(message: Message(
            role: .assistant,
            content: "It's currently 72°F and sunny in Houston. Perfect weather for being outside!"
        ))
        
        MessageBubble(message: Message(
            role: .user,
            content: "Thanks!"
        ))
    }
    .padding()
}
