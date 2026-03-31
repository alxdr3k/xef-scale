module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!

      private

      def authenticate_api_key!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        @api_key = ApiKey.authenticate(token)

        render(json: { error: "Invalid or missing API key" }, status: :unauthorized) unless @api_key
      end

      def current_workspace
        @api_key.workspace
      end

      def require_scope!(scope)
        return if @api_key.has_scope?(scope)
        render json: { error: "API key missing required scope: #{scope}" }, status: :forbidden
      end
    end
  end
end
