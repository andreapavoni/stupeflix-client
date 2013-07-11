# required API keys
$stupeflixAccessKey = ENV["STUPEFLIX_KEY"]
$stupeflixSecretKey = ENV["STUPEFLIX_SECRET"]

# These are optional variables, by default read from the environement variables,
# but you can too override them with your own credentials directly

$youtubeLogin = ENV["YOUTUBE_LOGIN"]
$youtubePassword = ENV["YOUTUBE_PASSWORD"]
$s3AccessKey = ENV["S3_ACCESS_KEY"]
$s3SecretKey = ENV["S3_SECRET_KEY"]
$s3Bucket = ENV["S3_BUCKET"]
$httpUploadPrefix = ENV["HTTP_UPLOAD_PREFIX"]

if ENV["STUPEFLIX_TEST_TIME"]  == nil
  t = Time.now
  $dateString = t.strftime("%Ya%ma%da%Ha%Ma%S")
else
  $dateString = ENV["STUPEFLIX_TEST_TIME"]
end

$filename = ENV["STUPEFLIX_MOVIE"]
if $filename == nil
    $filename = "movie.xml"
end
