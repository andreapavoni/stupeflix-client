require 'openssl'
require 'digest'
require 'base64'
require 'stupeflix/connection'
require 'digest/md5'

module Stupeflix
  class Base
    def initialize( accessKey, privateKey, host = "http://services.stupeflix.com", service = 'stupeflix-1.0', debug = false)
      @accessKey = accessKey
      @privateKey = privateKey
      len = host.length - 7
      if host[host.length - 1, 1] == "/"
        host = host[0, host.length - 1]
      end

      @host = host[7,len]
      @base_url = service
      @debug = debug
      @service = service
      @TEXT_XML_CONTENT_TYPE = "text/xml"
      @APPLICATION_ZIP_CONTENT_TYPE = "application/zip"
      @APPLICATION_JSON_CONTENT_TYPE = "application/json"
      @APPLICATION_URLENCODED_CONTENT_TYPE = "application/x-www-form-urlencoded"
      @PROFILES_PARAMETER = "Profiles"
      @XML_PARAMETER = "ProfilesXML"
      @MARKER_PARAMETER = "Marker"
      @MAXKEYS_PARAMETER = "MaxKeys"
      # Currently there is only the Marker parameter (used for partial enumeration)
      @parametersToAdd = [@MARKER_PARAMETER, @MAXKEYS_PARAMETER]
      @sleepTime = 1.0
      @maxRetry = 4
      @base = true
    end

    def connectionGet
      return Connection.new(@host, "/" + @base_url)
    end

    def paramString( parameters)
      paramStr = ""
      if parameters != nil
        @parametersToAdd.each do |p|
          if parameters.include?(p)
            paramStr += sprintf( "%s\n%s\n", p, parameters[p])
          end
        end
      end
      return paramStr
    end

    def strToSign( method, resource, md5, mime, datestr, parameters)
      paramStr = paramString(parameters)
      stringToSign  = sprintf( "%s\n%s\n%s\n%s\n%s\n%s", method, md5, mime, datestr, '/' + @service + resource, paramStr)
      return stringToSign
    end

    def sign( strToSign, secretKey)
      digest  = OpenSSL::Digest::Digest.new('sha1')
      return OpenSSL::HMAC.hexdigest(digest, secretKey, strToSign)
    end

    def signUrl( url, method, md5, mime, parameters = {})
      now =Time.now.to_i
      strToSign = strToSign(method, url, md5, mime, now, parameters)
      signature = sign(strToSign, @privateKey)
      url += sprintf( "?Date=%s&AccessKey=%s&Signature=%s", now, @accessKey,signature)
      if parameters
        parameters.each_pair do |k,v|
          url += sprintf("&%s=%s", k,v)
        end
      end
      return url
    end

    def md5FileOrBody( filename, body = nil)
      md5 = Digest::MD5.new()

      if body != nil
        md5.update(body)
      else
        chunksize=1024
        f = File.open(filename, 'r')

        while true
          chunk = f.read(chunksize)
          if not chunk
            break
          end
          md5.update(chunk)
        end
        f.close
      end

      digest = md5.digest

      return [digest, md5.hexdigest, Base64.encode64(digest).strip]
    end

    def isZip( filename)
      f = File.open(filename, 'r')
      header = f.read(4)
      return header == 'PK'+3.chr+4.chr
    end

    def logdebug( s)
      if @debug
        print s.to_s
      end
    end

    def error( message)
      logdebug(message)
      raise StandardError, message
    end

    def answer_error( answer, message)
      raise StandardError, sprintf( "%s\n%s", message,  answer['body'])
    end

    # sendcallback is an object with
    #  - a 'sendCallBack' member function that accept a unique int argument (=number of bytes written so far)
    #  - a 'sendBlockSize' member function with no argument which return the size of block to be sent
    def sendContent( method, url, contentType, filename = nil, body = nil,  parameters = nil, sendcallback = nil)

      # SEND DATA
      conn = connectionGet()

      md5, md5hex, md5base64 = md5FileOrBody(filename, body)

      if filename
        size = File.stat(filename).size
      else
        size = body.length
      end

      headers = {'Content-MD5' => md5base64.to_s,
                 'Content-Length' => size.to_s,
                 'Content-Type' => contentType}

      url = signUrl(url, method, md5base64, contentType, parameters)

      # LAUNCH THE REQUEST : TODO : pass filename instead of body
      if method == "PUT"
        answer = conn.request_put(url, args = nil, body = body, filename = filename, headers = headers, sendcallback = sendcallback)
      elsif method == "POST"
        answer = conn.request_post(url,  args = nil, body = body, filename = filename, headers = headers)
      elsif method == "DELETE"
        answer = conn.request_delete(url, headers = headers)
      end

      headers = answer['headers']

      logdebug(headers)
      logdebug(answer['body'])

      # NOW CHECK THAT EVERYTHING IS OK
      status = headers['status']
      if status != '200'
        msg = sprintf( "sendContent : bad STATUS %s", status )
        answer_error(answer, msg)
      end

      if headers['etag'] == nil
        msg = "corrupted answer: no etag in headers. Response body is " + answer['body']
        error(msg)
      end

      obtainedMD5 = headers['etag']

      if obtainedMD5 != md5hex
        msg = sprintf( "sendContent : bad returned etags %s =! %s (ref)", obtainedMD5, md5hex)
        error(msg)
      end

      return answer
    end

    def getContentUrl( url, method, parameters)
      return signUrl(url, method, "", "", parameters)
    end

    def getContent( url, filename = nil, parameters = nil)
      sleepTime = @sleepTime

      for i in 0..@maxRetry
        raiseExceptionOn404 = (i + 1) == @maxRetry
        ret = getContent_(url, filename, parameters, raiseExceptionOn404)
        if ret["status"] != 404
          return ret
        end
        # Wait for amazon S3 ...
        sleep(1)
      end
    end

    def getContent_( url, filename = nil, parameters = nil, raiseExceptionOn404 = true)
      method = "GET"
      url = getContentUrl(url, method, parameters)

      # GET DATA
      conn = connectionGet()
      answer = conn.request_get(url)
      body = answer['body']

      headers = answer['headers']
      status = headers['status'].to_i

      if status == 204
        # there was no content
        obtainedSize = 0
        if body.length != 0
          error("204 status with non empty body.")
        end
      elsif status == 200
        obtainedSize =headers['content-length'].to_i
      elsif status == 404 and not raiseExceptionOn404
        return  {"url" => headers['content-location'], "status" => 404}
      else
        msg = sprintf( "getContent : bad STATUS %s", status )
        answer_error(answer, msg)
      end

      if body.length != obtainedSize
        error("Non matching body length and content-length")
      end

      if filename != nil
        f = File.open(filename, 'w')
        f.write(body)
        f.close

        if obtainedSize == 0
          File.unlink(filename)
        else
          filesize = File.stat(filename).size
          if obtainedSize != filesize
            File.unlink(filename)
            error(sprintf( "file size is incorrect : file size = %d, body size = %d", filesize, obtainedSize))
          end
        end
      end

      # NOW CHECK EVERYTHING IS OK
      md5, md5hex, md5base64 = md5FileOrBody(filename, body)

      if status != 204
        obtainedMD5 = headers['etag'].gsub(/"/,"")
        if obtainedMD5 != md5hex
          if filename
            File.unlink(filename)
          end
          error(sprintf( "getDefinition : bad returned etag %s =! %s (ref)", md5hex, obtainedMD5))
        end
      end

      if status == 200
        logdebug(sprintf( "headers = %s", headers) )
        url = headers['content-location']
        ret = {'size' => obtainedSize, 'url' => url, 'headers' =>  headers}
      else
        ret = {'size' => obtainedSize, 'url' => url}
      end

      if not filename
        ret['body'] = body
      end

      ret["status"] = status

      return ret
    end
  end
end
