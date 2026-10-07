#!/bin/bash
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
set -euo pipefail
mkdir -p build
xcrun simctl list devices available -j | ruby -rjson -e '
  devices = JSON.parse(STDIN.read)["devices"]
  runtimes = devices.keys.select { |k| k.include?("iOS") }
                         .sort_by { |k| k.scan(/\d+/).map(&:to_i) }
                         .reverse
  runtimes.each do |rt|
    phone = devices[rt].find { |d| d["name"].start_with?("iPhone") }
    if phone
      puts phone["udid"]
      exit 0
    end
  end
  STDERR.puts "No iPhone simulator found"
  exit 1
'
