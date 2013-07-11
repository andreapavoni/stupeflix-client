require 'net/http'
require 'uri'

module Stupeflix
  class Connection
    def initialize(server, base_url)
      @server = server
      @base_url = base_url
      @MAX_NETWORK_RETRY = 1
      @debuglevel = 0
    end

    def request_get( resource, args = nil, headers={})
      return request(resource, "get", args, body = nil, filename = nil, headers=headers)
    end

    def request_delete( resource, args = nil, headers={})
      return request(resource, "delete", args, headers=headers)
    end

    def request_head( resource, args = nil, headers={})
      return request(resource, "head", args, headers=headers)
    end

    def request_post( resource, args = nil, body = nil, filename=nil, headers={})
      return request(resource, "post", args , body = body, filename=filename, headers=headers)
    end

    def request_put(resource, args = nil, body = nil, filename=nil, headers={}, sendcallback = nil)
      dump("In request_put in connection", resource, "PUT")
      resp = request(resource, "put", args , body = body, filename=filename, headers=headers, sendcallback = sendcallback)
      return resp
    end

    def dump( message, request_uri, method)
      if @debuglevel > 0
        print message, " " , time.asctime, " " , request_uri, "\n"
      end
    end

    def request_method(verb)
      Net::HTTP.const_get(verb.to_s.capitalize)
    end

    def fetch(uri_str, limit = 10)
      # You should choose better exception.
      raise ArgumentError, 'HTTP redirect too deep' if limit == 0

      response = Net::HTTP.get_response(URI.parse(uri_str))
      case response
      when Net::HTTPSuccess     then response
      when Net::HTTPRedirection then fetch(response['location'], limit - 1)
      else
        response.error!
      end

    end

    def request( resource, method = "get", args = nil, body = nil, filename=nil, headers={}, sendcallback = nil)
      params = nil
      path = resource
      headers ||= {}

      headers['User-Agent'] = 'Basic Agent'

      if method != "get"
        if !body and filename
          bodystream = File.open(filename, 'r')
        end
      end

      path += "?" + urllib.urlencode(args) if args
      url = "http://#{@server}#{@base_url}#{path}"

      dump("Connection Request starting", path, method.upcase)

      for i in 0..@MAX_NETWORK_RETRY
        begin
          #        http.set_debug_output $stdout
          #        headers['Expect'] = '100-Continue'

          response = nil
          while true
            url = URI.parse(url)
            request = request_method(method).new(url.path + "?" + url.query, headers)
            if bodystream
              request.body_stream = bodystream
            elsif body
              request.body = body
            end
            http = Net::HTTP.new(url.host, url.port)
            result = http.start {|http| response = http.request(request) }
            case response
            when Net::HTTPRedirection
              then
              url = response['location']
            else
              break
            end
          end
          break
        rescue StandardError => e
          if i == (@MAX_NETWORK_RETRY - 1)
            raise
          end
        end
      end
      response["status"] = response.code.to_s
      return {'headers' => response, 'body' => response.body}
    end

  end
end
