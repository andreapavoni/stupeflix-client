require 'stupeflix/version'
require 'stupeflix/connection'
require 'stupeflix/base'
require 'cgi'
require 'json'

module Stupeflix
  class StupeflixClient < Base
    def initialize(accessKey, privateKey, host = "http://services.stupeflix.com", service = 'stupeflix-1.0', debug = false)
      super(accessKey, privateKey, host, service, debug)
      @batch = false
      @batchData = ""
    end

    # Start a batch, used for speeduping video definition upload
    # Operation that can be batched : sendDefinition and createProfiles
    # Operation
    # Only works for xml definition, not zip, and xml must be in UTF8
    def batchStart( maxSize = 1000000)
      @batch = true
      @batchData = "<batch>"
      @batchMaxSize = maxSize
    end

    # End a batch: actually send data
    def batchEnd
      @batchData += "</batch>"
      sendDefinitionBatch(body = @batchData)
      @batchData = ""
      @batch = false
    end

    # Send a definition file to the API
    def sendDefinition( user, resource, filename = nil, body = nil)
      url = definitionUrl(user, resource)
      if body
        contentType = @TEXT_XML_CONTENT_TYPE;
      elsif isZip(filename)
        contentType = @APPLICATION_ZIP_CONTENT_TYPE
      else
        contentType = @TEXT_XML_CONTENT_TYPE
      end
      if @batch and contentType == @TEXT_XML_CONTENT_TYPE
        @batchData += sprintf("<task user=\"%s\" resource=\"%s\">", user, resource)
        if body
          @batchData += body
        else
          @batchData += File.open(filename).read
        end
      else

        return sendContent("PUT", url, contentType, filename, body)
      end
    end

    # Send a definition file to the API
    def sendDefinitionBatch( filename = nil, body = nil)
      url = @definitionBatchUrl
      contentType = @TEXT_XML_CONTENT_TYPE;
      return sendContent("PUT", url, contentType, filename, body)
    end

    def getDefinition( user, resource, filename)
      url = definitionUrl(user, resource)
      return getContent(url, filename)['size']
    end

    def _getAbsoluteUrl( url, followRedirect = false)
      urlPart = getContentUrl(url, 'GET', nil)
      if followRedirect
        conn = connection.Connection(@base_url, followRedirect = false)
        response = conn.request_get(urlPart)
        return response["headers"]["location"]
      else
        return @base_url + urlPart
      end
    end

    def getProfileUrl( user, resource, profile, followRedirect = false)
      url = profileUrl(user, resource, profile)
      return _getAbsoluteUrl(url, followRedirect)
    end

    def getProfile( user, resource, profile, filename)
      url = profileUrl(user, resource, profile)
      getContent(url, filename)
    end

    def getProfileThumbUrl( user, resource, profile, followRedirect = false)
      url = profileThumbUrl(user, resource, profile, "thumb.jpg")
      return _getAbsoluteUrl(url, followRedirect)
    end

    def getProfileThumb( user, resource, profile, filename)
      url = profileThumbUrl(user, resource, profile, "thumb.jpg")
      getContent(url, filename)
    end

    def getProfileReportUrl( user, resource, profile, followRedirect = false)
      url = profileReportUrl(user, resource, profile)
      return _getAbsoluteUrl(url, followRedirect)
    end

    def getProfileReport( user, resource, profile, filename)
      url = profileReportUrl(user, resource, profile)
      getContent(url, filename)
    end

    def createProfiles( user, resource, profiles)
      profileData = profiles.xmlGet
      if @batch
        @batchData += profileData
        @batchData += "</task>"
        if @batchData.length >= @batchMaxSize
          begin
            @batchEnd
            finally
            batchStart(@batchMaxSize)
          end
        end
      else
        url, parameters = profileCreateUrl(user, resource, profileData)
        contentType = @APPLICATION_URLENCODED_CONTENT_TYPE
        body = ""
        parameters.each_pair do |k,v|
          body += CGI::escape(k) + "=" + CGI::escape(v)
        end
        return sendContent("POST", url, contentType, filename = nil, body = body)
      end
    end

    def getStatus( user = nil, resource = nil, profile = nil, marker = nil, maxKeys = nil)
      url, parameters = statusUrl(user, resource, profile, marker, maxKeys)
      ret = getContent(url, filename = nil, parameters = parameters)
      status = JSON.parse(ret['body'])
      return status
    end

    def getMarker( status)
      if status.length == 0
        return nil
      end
      lastStatus = status[-1]
      #return map(lambda x: lastStatus[x], ["user", "resource", "profile"])
      return []
    end

    # helper functions : build non signed urls for each kind of action
    def definitionUrl( user, resource)
      return sprintf( "/%s/%s/definition/", user, resource)
    end

    # helper functions : build non signed urls for each kind of action
    def definitionBatchUrl
      return "/batch/"
    end

    def profileUrl( user, resource, profile)
      return sprintf( "/%s/%s/%s/", user, resource, profile)
    end

    def profileThumbUrl( user, resource, profile, thumbname)
      return sprintf( "/%s/%s/%s/%s/", user, resource, profile, thumbname)
    end

    def profileReportUrl( user, resource, profile)
      return sprintf( "/%s/%s/%s/%s/", user, resource, profile, "report.xml")
    end

    def profileCreateUrl( user, resource, profiles)
      s = sprintf( "/%s/%s/", user, resource)
      parameters = {@XML_PARAMETER => profiles}
      return s, parameters
    end

    def actionUrl( user, resource, profile, action)
      path = [user, resource, profile]
      s = ""
      path.each do |p|
        if p == nil
          break
        end
        s += sprintf( "/%s", p )
      end
      s += sprintf( "/%s/", action )
      return s
    end

    def statusUrl( user, resource, profile, marker = nil, maxKeys = nil)
      params = {}
      if marker != nil
        params[@MARKER_PARAMETER] = marker.join('/')
      end
      if maxKeys != nil
        params[@MAXKEYS_PARAMETER] = maxKeys
      end

      return [actionUrl(user, resource, profile, "status"), params]
    end
  end

  class StupeflixXMLNode
    def initialize( nodeName, attributes = nil, children = nil, text = nil)
      @children = children
      @attributes = attributes
      @nodeName = nodeName
      @text = text
    end

    def xmlGet
      docXML = '<' + @nodeName
      if @attributes and @attributes.length != 0

        @attributes.each_pair do |k, v|
          docXML += " "
          if v == nil
            v = ""
          end
          k = k.to_s
          v = v.to_s
          docXML += k + '="' + CGI.escapeHTML(v) + '"'
        end
      end
      docXML += '>'
      if @children
        for c in @children
          docXML += c.xmlGet
        end
      end
      if @text
        docXML += @text
      end
      docXML += '</' + @nodeName + '>'

      return docXML
    end

    def metaChildrenAppend( meta = nil, notify = nil, children = nil)
      childrenArray = []
      if meta
        childrenArray += [meta]
      end
      if notify
        childrenArray += [notify]
      end
      if children
        childrenArray += children
      end
      return childrenArray
    end
  end

  class StupeflixMeta < StupeflixXMLNode
    def initialize(dict)
      children = []

      dict.all? {|k, v|
        children += [StupeflixXMLNode.new(k, nil, nil, v)]
      }
      super("meta", {}, children)
    end
  end

  class StupeflixProfileSet < StupeflixXMLNode
    def initialize( profiles, meta = nil, notify = nil)
      children = metaChildrenAppend(meta, notify, profiles)
      super("profiles", {}, children)
    end

    def deflt(profiles)
      profSet = []
      for p in profiles
        upload = StupeflixDefaultUpload
        profSet += [StupeflixProfile(p, [upload])]
      end

      return  StupeflixProfileSet.new(profSet)
    end
  end

  class StupeflixProfile < StupeflixXMLNode
    def initialize( profileName, uploads = nil, meta = nil, notify = nil)
      children = metaChildrenAppend(meta, notify, uploads)
      super("profile", {"name" => profileName}, children)
    end
  end

  class StupeflixNotify < StupeflixXMLNode
    def initialize( url, statusRegexp)
      super("notify", {"url" => url, "statusRegexp" => statusRegexp})
    end
  end

  class StupeflixHttpHeader < StupeflixXMLNode
    def initialize(key, value)
      super("header", {"key" => key, "value" => value})
    end
  end

  class StupeflixUpload < StupeflixXMLNode
    def initialize( name, parameters, meta = nil, notify = nil, children = nil)
      children = metaChildrenAppend(meta, notify, children)
      super(name, parameters, children)
    end
  end

  class StupeflixHttpPOSTUpload < StupeflixUpload
    def initialize( url, meta = nil, notify = nil)
      super("httpPOST", {"url" => url}, meta, notify)
    end
  end

  class StupeflixHttpPUTUpload < StupeflixUpload
    def initialize( url, meta = nil, notify = nil, headers = nil)
      super("httpPUT", {"url" => url}, meta, notify, headers)
    end
  end

  class StupeflixYoutubeUpload < StupeflixUpload
    def initialize(login, password, meta = nil, notify = nil)
      super("youtube", {"login" => login, "password" => password}, meta, notify)
    end
  end

  class StupeflixBrightcoveUpload < StupeflixUpload
    def initialize(token, reference_id = nil, meta = nil, notify = nil)
      parameters = {"sid" => token}
      if reference_id != nil
        parameters["reference_id"] = reference_id
      end
      super("brightcove", parameters, meta, notify)
    end
  end

  class StupeflixDefaultUpload < StupeflixUpload
    def initialize( meta = nil, notify = nil)
      children = metaChildrenAppend(meta)
      super("stupeflixStore", {}, meta, notify)
    end
  end

  class StupeflixS3Upload < StupeflixUpload
    def initialize(bucket, resourcePrefix, accesskey = nil, secretkey = nil, meta = nil, notify = nil)
      children = metaChildrenAppend(meta)
      parameters = {"bucket" => bucket, "resourcePrefix" => resourcePrefix}
      if accesskey != nil
        parameters["accesskey"] = accesskey
      end
      if secretkey != nil
        parameters["secretkey"] = secretkey
      end
      super("s3", parameters, meta, notify)
    end
  end
end
