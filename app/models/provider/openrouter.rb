class Provider::Openrouter < Provider
  include LlmConcept

  Error = Class.new(Provider::Error)

  BASE_URL = "https://openrouter.ai/api/v1"

  def initialize(access_token, models: [])
    @access_token = access_token
    @supported_models = models
  end

  def supports_model?(model)
    @supported_models.include?(model)
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil)
    with_provider_response do
      messages = build_messages(prompt, instructions: instructions, function_results: function_results)
      tools = build_tools(functions)

      body = {
        model: model,
        messages: messages,
        stream: streamer.present?
      }
      body[:tools] = tools if tools.any?

      if streamer.present?
        stream_response(body, streamer)
      else
        sync_response(body)
      end
    end
  end

  # OpenRouter doesn't support auto-categorize/merchant detection via Responses API
  # These features require OpenAI directly
  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response do
      raise Error, "Auto-categorize requires OpenAI provider"
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Auto-detect merchants requires OpenAI provider"
    end
  end

  private

    attr_reader :access_token, :supported_models

    def build_messages(prompt, instructions: nil, function_results: [])
      messages = []
      messages << { role: "system", content: instructions } if instructions.present?
      messages << { role: "user", content: prompt }

      function_results.each do |fn_result|
        # Add the tool call that triggered this result
        messages << {
          role: "assistant",
          tool_calls: [{
            id: fn_result[:call_id],
            type: "function",
            function: { name: fn_result[:name] || "function", arguments: "{}" }
          }]
        }
        messages << {
          role: "tool",
          tool_call_id: fn_result[:call_id],
          content: fn_result[:output].to_json
        }
      end

      messages
    end

    def build_tools(functions)
      functions.map do |fn|
        {
          type: "function",
          function: {
            name: fn[:name],
            description: fn[:description],
            parameters: fn[:params_schema]
          }
        }
      end
    end

    def sync_response(body)
      response = client.post("#{BASE_URL}/chat/completions") do |req|
        req.body = body.to_json
      end

      parsed = JSON.parse(response.body)
      raise Error, parsed.dig("error", "message") || "Unknown error" if parsed["error"]

      parse_completion(parsed)
    end

    def stream_response(body, streamer)
      collected_text = ""
      collected_tool_calls = []
      response_id = nil
      response_model = nil

      client.post("#{BASE_URL}/chat/completions") do |req|
        req.body = body.to_json
        req.options.on_data = proc do |chunk, _size, _env|
          chunk.split("\n").each do |line|
            next unless line.start_with?("data: ")
            data = line.sub("data: ", "").strip
            next if data == "[DONE]"

            begin
              parsed = JSON.parse(data)
              response_id ||= parsed["id"]
              response_model ||= parsed["model"]

              delta = parsed.dig("choices", 0, "delta")
              next unless delta

              if delta["content"]
                collected_text += delta["content"]
                streamer.call(ChatStreamChunk.new(type: "output_text", data: delta["content"]))
              end

              if delta["tool_calls"]
                delta["tool_calls"].each do |tc|
                  idx = tc["index"]
                  collected_tool_calls[idx] ||= { id: "", function: { name: "", arguments: "" } }
                  collected_tool_calls[idx][:id] = tc["id"] if tc["id"]
                  collected_tool_calls[idx][:function][:name] += tc.dig("function", "name") || ""
                  collected_tool_calls[idx][:function][:arguments] += tc.dig("function", "arguments") || ""
                end
              end
            rescue JSON::ParserError
              next
            end
          end
        end
      end

      # Build final response
      messages = []
      if collected_text.present?
        messages << ChatMessage.new(id: response_id, output_text: collected_text)
      end

      fn_requests = collected_tool_calls.compact.map do |tc|
        ChatFunctionRequest.new(
          id: tc[:id],
          call_id: tc[:id],
          function_name: tc[:function][:name],
          function_args: tc[:function][:arguments]
        )
      end

      final_response = ChatResponse.new(
        id: response_id,
        model: response_model,
        messages: messages,
        function_requests: fn_requests
      )

      streamer.call(ChatStreamChunk.new(type: "response", data: final_response))
      final_response
    end

    def parse_completion(parsed)
      choice = parsed.dig("choices", 0)
      message = choice&.dig("message")

      messages = []
      if message&.dig("content").present?
        messages << ChatMessage.new(
          id: parsed["id"],
          output_text: message["content"]
        )
      end

      fn_requests = (message&.dig("tool_calls") || []).map do |tc|
        ChatFunctionRequest.new(
          id: tc["id"],
          call_id: tc["id"],
          function_name: tc.dig("function", "name"),
          function_args: tc.dig("function", "arguments")
        )
      end

      ChatResponse.new(
        id: parsed["id"],
        model: parsed["model"],
        messages: messages,
        function_requests: fn_requests
      )
    end

    def client
      @client ||= Faraday.new(url: BASE_URL) do |f|
        f.request :retry, max: 2, interval: 0.5
        f.response :raise_error
        f.headers["Authorization"] = "Bearer #{access_token}"
        f.headers["Content-Type"] = "application/json"
        f.headers["HTTP-Referer"] = "https://maybefinance.com"
        f.headers["X-Title"] = "Maybe Finance"
      end
    end
end
