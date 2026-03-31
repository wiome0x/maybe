module Maybe
  class << self
    def version
      Semver.new(semver)
    end

    def commit_sha
      @commit_sha ||= begin
        if Rails.env.production?
          ENV["BUILD_COMMIT_SHA"].presence || git_commit_sha
        else
          git_commit_sha
        end
      end
    end

    private
      def semver
        @semver ||= begin
          tag = `git describe --tags --abbrev=0 2>/dev/null`.chomp
          tag.present? ? tag.sub(/\Av/, "") : "0.0.0"
        end
      end

      def git_commit_sha
        `git rev-parse HEAD 2>/dev/null`.chomp.presence
      end
  end
end
