# -*- coding: utf-8 -*-
$:.unshift("/Library/RubyMotion/lib")
require 'motion/project'

Motion::Project::App.setup do |app|
  # Use `rake config' to see complete project settings.
  app.name = 'Journal'

  app.frameworks += %w{ CoreData }

  app.vendor_project('vendor/incremental_store', :static, :cflags => "-fobjc-arc")

  # By passing the `data_directory=*something*` environment variable to Rake,
  # you can change where the application reads and writes the data store. Note
  # this only make sense when building and running on the simulator.
  if ENV['data_directory']
    puts "Building app with data directory: #{ENV['data_directory']}"
    app.info_plist['APP_DataDirectory'] = File.expand_path(ENV['data_directory'])
  else
    app.info_plist['APP_DataDirectory'] = "default"
  end
end
