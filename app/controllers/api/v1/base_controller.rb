module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!

      private

      def authenticate_api_key!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        @api_key = ApiKey.authenticate(token)

        unless @api_key
          render json: { error: "Invalid or missing API key" }, status: :unauthorized
          return
        end
      end

      def current_workspace
        @api_key.workspace
      end
    end
  end
end
