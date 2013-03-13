Core Data Journal App in RubyMotion
===================================

This is the sample code that goes along with my talk, [Core Data For The Curious Rubyist][cd], that I gave at the first [RubyMotion #inspect conference][inspect] in Brussels, Belgium. It demonstrates raw Core Data usage, no external dependencies required. And it demonstrates a custom persistent store that writes simple entities to text files in the documents directory. You can use this as a starting point to understand how Core Data works and them build on it or use third party tools like [Motion Data][md].

  [cd]: http://cocoamanifest.net/features/2013-03-core-data-in-motion.pdf
  [inspect]: http://www.rubymotion.com/conference/
  [md]: https://github.com/alloy/MotionData

It's just a simple journal app that lets you create and remove text entries.

## Setup

Download and run `rake`. Yup, that's all you need.

## How It Works

`app/app_delegate.rb` - This bootstraps the application with a navigation controller and the entry table view controller.

`app/document.rb` - This document holds the Core Data stack---the store coordinator, the model, and the root context. Create an instance of this and you're ready to go.

`app/journal_entry.rb` - A simple subclass of `NSManagedObject` with some helper methods to make creating and fetching journal entries a little easier.

`app/entry_table_view_controller.rb` - The table view controller that builds an `NSFetchedResultsController` to watch an ordered list of entries and display them at the appropriate index paths in the table view. It lets you create and remove journal entries and run the "hammer" to watch the app while the file system changes.

`app/hammer.rb` - This object lets you spin up a background queue that randomly creates and removes files in the custom persistent store directory. That way, you can watch the custom persistent store as it sees changes and notifies the application to keep the interface up to date. It is triggered in the `EntryTableViewController`.

`resources/IncrementalStoreTest.xcdatamodeld` - This is the Xcode model package that RubyMotion can automatically compile into the app bundle. Double click this to see it in Xcode's visual modeler.

`vendor/incremental_store/MyIncrementalStore.m` - This is the custom incremental store to show off Core Data's decoupled power. This store writes the journal entries to simple text files in the destination directory. But it also watches that directory for changes and updates the root context of the document so that the rest of the application can be notified.

I had to write this in Objective C because there was an odd memory leak when I originally wrote it in RubyMotion and I didn't think it was worth it to dig in and find out why at this time.

## Contact

Questions? Ask!

Jonathan Penn

- http://cocoamanifest.net
- http://github.com/jonathanpenn
- http://twitter.com/jonathanpenn
- http://alpha.app.net/jonathanpenn
- jonathan@cocoamanifest.net

## License

Journal is available under the MIT license. See the LICENSE file for more info.
