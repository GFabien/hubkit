module Hubkit
  class Client
    module Connection
      def get(path, options = {})
        request :get, path, options
      end

      def post(path, options = {})
        options[:headers] ||= {}
        options[:headers].merge!({ 'Content-Type' => 'application/json' })
        request :post, path, options
      end

      private

      def request(http_method, path, options)
        retries = 2
        begin
          response = call(http_method, path, options)
          case response.parsed_response
            when Hash then Hashie::Mash.new(response.parsed_response)
            when Array then response.parsed_response.map {|hash| Hashie::Mash.new(hash) }
            when nil then nil
            else response.parsed_response
          end
        rescue Hubkit::UnauthorizedError
          if retries.positive?
            retries -= 1
            retry
          end
          raise
        end

      end

      def call(http_method, path, options)
        response = self.class.send(http_method, path, options)

        case response.code
          when 200
            return response
          when 401
            authenticate!
            raise Hubkit::UnauthorizedError
          else
            raise Hubkit::Error, response.parsed_response['message']
          end
      end

      def authenticate!
        response = self.class.post('/oauth/v1/token', body: {
          grant_type: 'refresh_token',
          client_id: @client_id,
          client_secret: @client_secret,
          refresh_token: @refresh_token
        })

        if response.code != 200
          raise Hubkit::Error, response.parsed_response['message']
        end

        data = Hashie::Mash.new(response.parsed_response)

        self.oauth_token = data.access_token
        self.token_expires_in = data.expires_in

        @authentication_callback&.call(data)
        data
      end
    end
  end
end
