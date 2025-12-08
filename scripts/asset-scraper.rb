#!/usr/bin/env ruby

# Copyright: (C) 2024 iCub Tech Facility - Istituto Italiano di Tecnologia
# Authors: Ugo Pattacini <ugo.pattacini@iit.it>


#########################################################################################
# deps
require 'octokit'
require 'uri'
require 'open3'

#########################################################################################
# global vars
$token = ENV['GH_ASSET_SCRAPER_PAT']
$client = Octokit::Client.new :access_token => $token

#########################################################################################
# traps
Signal.trap("INT") {
  exit 2
}

Signal.trap("TERM") {
  exit 2
}


#########################################################################################
def check_and_wait_until_reset
    rate_limit = $client.rate_limit
    if rate_limit.remaining <= 10 then
        reset_secs = rate_limit.resets_in + 60
        reset_mins = reset_secs / 60
        puts ""
        puts "⏳ We hit the GitHub API rate limit; reset will occur at #{rate_limit.resets_at}"
        puts "⏳ Process suspended for #{reset_mins} mins"
        sleep(reset_secs)
        puts "⏳ Process recovered ✔"
        puts ""
    end
end


#########################################################################################
# main

# retrieve information from command line
repo = ARGV[0]
input_dir = ARGV[1];
asset_dir = ARGV[2];
prefix_dir = ARGV[3];

# cycle over files
Dir.entries(input_dir).each { |f| 
    filename = File.join(input_dir, f)
    if File.file?(filename) then
        puts "📄 Processing file \"#{filename}\""
        text = File.read(filename)

        # cycle over URLs
        update_file = false
        URI.extract(text).each { |uri|
            if uri.include?("github.com/user-attachments/assets") || uri.include?(repo + "/assets") then
                # Trimming URL:
                # Remove any character at the end ($) that is NOT (^) alphanumeric ([a-zA-Z0-9])
                # The '+' means "one or more", so it handles multiple trailing chars like ")."
                uri = uri.sub(/[^a-zA-Z0-9]+$/, '')
                puts  "  🌐 Found asset at URI: \"#{uri}\""

                # download asset
                asset_name = asset_dir + "/" + File.basename(uri)
                check_and_wait_until_reset
                print "    ⬇️  Downloading \"#{asset_name}\"... "
                system("curl --header 'Authorization: token #{$token}' \\
                             --header 'Accept: application/vnd.github.v3.raw' \\
                             --location #{uri} \\
                             --create-dirs --output #{asset_name} \\
                             --silent")
                puts  "✅"

                # rename asset with the correct extension
                stdout, stderr, status = Open3.capture3("file --mime #{asset_name}")
                mime_type = stdout.split[1]
                ext = mime_type.split("/")[1][0..2]
                asset_name_ext = asset_name + "." + ext
                print "    ➡️  Renaming into \"#{asset_name_ext}\"... "
                File.rename("#{asset_name}", "#{asset_name_ext}")
                puts  "✅"

                # scrape the file to replace the URL with the local asset
                print "    🔁 Replacing asset URI with \"#{asset_name_ext}\"... "
                text = text.gsub(uri, prefix_dir + "/" + File.basename(uri) + "." + ext)
                puts  "✅"

                update_file = true
            end
        }

        # update file if needed
        if update_file then
            File.open(filename, "w") { |file|
                print "  📝 Updating file... "
                file << text
                puts  "✅"
            }
        end
    end
}
