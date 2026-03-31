module ChatsHelper
  def chat_frame
    :sidebar_chat
  end

  def chat_view_path(chat)
    return new_chat_path if params[:chat_view] == "new"
    return chats_path if chat.nil? || params[:chat_view] == "all"

    chat.persisted? ? chat_path(chat) : new_chat_path
  end

  def available_ai_model
    registry = Provider::Registry.for_concept(:llm)
    provider = registry.providers.compact.first
    return "gpt-4.1" unless provider # fallback

    if provider.is_a?(Provider::Openrouter)
      ENV.fetch("OPENROUTER_MODELS", "google/gemini-2.5-flash").split(",").first.strip
    else
      "gpt-4.1"
    end
  end
end
