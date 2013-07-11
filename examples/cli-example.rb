require_relative "conf"
require "stupeflix"
require "Time"

class StupeflixTest
  # including the Stupeflix module here, to avoid to specify namespece
  include Stupeflix

  def initialize()
    # Create the client to access the API
    # You can safely assume that $stupeflixHost is nil
    @client = StupeflixClient.new($stupeflixAccessKey, $stupeflixSecretKey)

    # Set the name for the resource to be created
    # These names are alphanumerical, and can be set to whatever you want
    @user = "test"
    @resource = "resource" + $dateString

    # Configuration for s3 retries
    @s3Retries = 5
    @s3Wait = 1
    # Set this to true if you want to see the status of videos being generated
    @debug = false
  end

  def uploadsCreate(profileName)
    user = @user
    resource = @resource
    # Array of uploads to be filled in
    uploads = []

    # Default upload creation : will store to the stupeflix s3 bucket
    # This is not mandatory, just a easy way to store temporarily the result of the video generation.
    uploads += [StupeflixDefaultUpload.new()]

    # YouTube upload creation, if correct information was entered in conf.rb
    if $youtubeLogin != nil
      # Create sample youtube information
      tags = ["these","are","my","tags"].join(",")
      youtubeInfo = {"title" => "Upload test "  + $dateString,
        "description"=> "Upload test description" + $dateString,
        "tags"=>tags,
        "channels"=>"Tech",
        "acl"=>"public",
        "location"=>"49,-3"}

      youtubeMeta = StupeflixMeta.new(youtubeInfo)

      # There is no currently notification
      youtubeNotify = nil
      uploads += [StupeflixYoutubeUpload.new($youtubeLogin, $youtubePassword, youtubeMeta, youtubeNotify)]
    end

    # S3 Upload creation : upload to your own S3 bucket
    if $s3AccessKey != nil
      s3resource = "%s/%s/%s" % [user, resource, "iphone"]
      # Create s3 upload settings
      uploads += [StupeflixS3Upload.new(bucket=$s3Bucket, s3resource,  $s3AccessKey, $s3SecretKey)]
    end

    #  HTTP Uploads creation : POST and PUT
    if $httpUploadPrefix != nil
      # Create http POST upload settings
      postURL = $httpUploadPrefix + "post/%s/%s/%s" % [user, resource, profileName]
      uploads += [StupeflixHttpPOSTUpload.new(postURL)]

      # Create http PUT upload settings
      putURL = $httpUploadPrefix + "put/%s/%s/%s" % [user, resource, profileName]
      uploads += [StupeflixHttpPUTUpload.new(putURL)]
    end
    return uploads
  end

  def availableKey(rank, suffix = "id")
    return "available-" + rank.to_s() + "-" + suffix
  end

  # Check that all went fine, until every upoads is finished (or went on error)
  def waitForCompletion(uploadCount)
    error = false
    # Then wait for the generation to complete
    available = false
    status = nil
    error = false

    while not available and not error
      # Retrieve an array of status for every profiles for user and resource
      status = @client.getStatus(@user, @resource, nil)
      # Variable to test if every profile is available
      for s in status
        if @debug
          puts s
        end
        available = true
        for id in 0..uploadCount - 1
          availableKey = availableKey(id)
          availableType = availableKey(id, "type")
          if not s["status"].has_key?(availableKey)
            if @debug
              puts  "upload #" + id.to_s()  + " not yet ready for profile " + s["profile"]
            end
            available = false
            break
          else
            if @debug
                puts  "upload #" + id.to_s() + " '" + s["status"][availableType] + "' ready for profile " + s["profile"]
            end
          end
        end
        if s["status"]["status"] == "error"
          error = true
          break
        end
      end
      sleep(5)
    end
    # if available if false, that means that an error occurred
    return available, status
  end

  #Sometimes we have to wait for s3 to make the content available (this is in the Amazon S3 spec). This function is built to do just that.
  def s3WaitLoop()
    s3Wait = @s3Wait
    for i in 0..@s3Retries - 1
      begin
        yield nil
      rescue
        if (i + 1) == @s3Retries
          raise $!
        else
          sleep(s3Wait)
          s3Wait *= 2
        end
      end
    end
  end

  #This is the main function for creating videos, with main calls to the Stupeflix API.
  def run()
    profileNames = ["iphone"] # You can add profiles there :  "flash-small, quicktime, dvd ..."
    profileArray = []
    for profileName in profileNames
      uploads = uploadsCreate(profileName)
      # Create a new profile.
      profileArray += [StupeflixProfile.new(profileName, uploads = uploads)]
    end

    # Notification is not configured there : this consists in a series of HTTP POST ping requests to your own server.
    # This is much more powerful than polling the API as demonstrated in function waitForCompletion.
    notify = nil
    # Uncomment this line if you want to test notification. StatusRegexp is used to filter notification sent to your server.
    # Here, only final "available message" would be sent
    # notify =  StupeflixNotify.new(url = "http://myserver.com/mypath", statusRegexp = "available")

    # Create the set of profiles to be created
    profiles =  StupeflixProfileSet.new(profileArray, meta = nil, notify = notify)

    # This is only used to give proper names to output files (file names are appended with a proper extension)
    extensions = ["mp4"] # flv ...

    # Calls to the API start there

    # First send the movie definition file to the service. (see sample movie.xml in this directory)
    @client.sendDefinition(@user, @resource, $filename)

    # Then launch the generation, using the configuration we have built earlier
    @client.createProfiles(@user, @resource, profiles)

    # Poll the API, waiting for completion
    available, status = waitForCompletion(uploadCount = uploads.length)

    # Check if everything went fine
    if not available
      # Something went bad: at least some part of the task was not complete, but some may still have or even was uploaded.
      # This may happen for example if upload to youtube failed but upload to your own server succeeded.
      # an error occured, the status will give more information
      s = ""
      status.each {|element|
        s += [element["accesskey"], element["user"], element["resource"], element["profile"]].join(",")
        s += ":\n  "
        element["status"].sort.each { |key, value|
          s += "#{key} => #{value}, \n  "
        }
        s += "\n"
      }
      raise s
    end

    # Download all profiles
    i = 0
    profileNames.each do |p|
      # Print the profile url were the video can be found
      puts "movie url= " + @client.getProfileUrl(@user, @resource, p)
      movieName = "%smovie.%s"  % [p,  extensions[i]]
      puts "Download movie to file " + movieName
      s3WaitLoop { |n|
        @client.getProfile(@user, @resource, p, movieName)
      }

      # Download the profile thumb url
      thumbName = "thumb_%s.jpg" %  p
      puts "Download movie thumb to file " + thumbName
      s3WaitLoop { |n|
        @client.getProfileThumb(@user, @resource, p, thumbName)
      }

      i += 1
    end

    puts "Test succeeded."
  end
end


# Test if the keys were set
if $stupeflixAccessKey == nil
  puts "ERROR : Please fill in key information in conf.rb"
  exit(0)
end

test = StupeflixTest.new()
test.run()

