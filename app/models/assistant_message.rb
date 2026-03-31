class AssistantMessage < Message
  validates :ai_model, presence: true
  validates :content, presence: false  # content can be empty during streaming (function calls)

  def role
    "assistant"
  end

  def append_text!(text)
    self.content += text
    save!(validate: false)
  end
end
