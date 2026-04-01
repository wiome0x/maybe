module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_session

    def connect
      self.current_session = find_verified_session
    end

    rescue_from StandardError, with: :report_error

    private
      def find_verified_session
        cookie_value = cookies.signed[:session_token]
        session_record = Session.find_by(id: cookie_value) if cookie_value.present?
        session_record || reject_unauthorized_connection
      end

      def report_error(e)
        Sentry.capture_exception(e)
      end
  end
end
