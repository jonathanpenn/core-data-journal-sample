class EntryTableViewController < UITableViewController

  attr_reader :doc

  def viewDidLoad
    super
    @doc = Document.new
    setupNavBarButtons
    updateTitle
  end


  #
  # Table View Data Source Stuff
  #
  # These are the standard callbacks by the table view when it needs to know
  # how many sections, rows, populated cells, etc. We're also answering the
  # questions about editing cells so that the swipe to delete function works as
  # expected.
  #
  # We're talking to the fetchedResultsController through all of these methods
  # because that's the official way to tie a fetched results controller to a
  # table view. All the answers about how many sections/cells and what data
  # goes where is answered by the fetchedResultsController
  #

  def fetchedResultsController
    # The fetchedResultsController is created with a fetch request for journal
    # entities and tied to the root managed object context for the document.
    # Because we set ourselves as the delegate, we will get called back by the
    # fetched results controller when the data in the managed object context
    # changes. See the NSFetchedResultsControllerDelegate methods below.

    return @fetchedResultsController if @fetchedResultsController

    @fetchedResultsController = NSFetchedResultsController.alloc.initWithFetchRequest(
      JournalEntry.fetchRequest,
      managedObjectContext: doc.context,
      sectionNameKeyPath: nil,
      cacheName: nil)

    @fetchedResultsController.delegate = self

    error_ptr = Pointer.new(:object)
    if (!@fetchedResultsController.performFetch(error_ptr))
      raise ErrorWrapper.new(error_ptr[0])
    end

    @fetchedResultsController
  end

  def numberOfSectionsInTableView(tableView)
    fetchedResultsController.sections.count
  end

  def tableView(tableView, titleForHeaderInSection:section)
    fetchedResultsController.sectionIndexTitles[section]
  end

  def tableView(tableView, numberOfRowsInSection: section)
    sectionInfo = fetchedResultsController.sections[section]
    sectionInfo.numberOfObjects
  end

  def tableView(tableView, cellForRowAtIndexPath: path)
    cell = tableView.dequeueReusableCellWithIdentifier("Cell")
    if !cell
      cell = UITableViewCell.alloc.initWithStyle(
        UITableViewCellStyleSubtitle, reuseIdentifier: "Cell")
      cell.selectionStyle = UITableViewCellSelectionStyleNone
    end
    configureCell(cell, atIndexPath: path)
  end

  def tableView(tableView, canEditRowAtIndexPath: indexPath)
    true
  end

  def tableView(tableView, commitEditingStyle: editingStyle, forRowAtIndexPath: indexPath)
    if editingStyle == UITableViewCellEditingStyleDelete
      objectToDelete = fetchedResultsController.objectAtIndexPath(indexPath)
      doc.context.deleteObject(objectToDelete)
      doc.save!
    end
  end

  def configureCell(cell, atIndexPath: indexPath)
    if !@dateFormatter
      @dateFormatter = NSDateFormatter.alloc.init
      @dateFormatter.setDateStyle(NSDateFormatterShortStyle)
      @dateFormatter.setTimeStyle(NSDateFormatterLongStyle)
    end

    entry = fetchedResultsController.objectAtIndexPath(indexPath)
    cell.textLabel.font = UIFont.systemFontOfSize(13)
    cell.textLabel.text = entry.content
    cell.textLabel.sizeToFit
    cell.detailTextLabel.font = UIFont.systemFontOfSize(10)
    cell.detailTextLabel.text = @dateFormatter.stringFromDate(entry.timestamp)
    cell.detailTextLabel.sizeToFit
    cell
  end

  def tableView(tableView, editingStyleForRowAtIndexPath: indexPath)
    UITableViewCellEditingStyleDelete
  end


  #
  # NSFetchedResultsControllerDelegate methods
  #
  # These methods are called on us when the data in the managed object context
  # changes. There's nothing non-standard in these parts. This is boilerplate
  # from Apple's examples about tying a core data context to a table view
  # controller through an NSFetchedResultsController.
  #

  def controllerWillChangeContent controller
    tableView.beginUpdates
  end

  def controllerDidChangeContent controller
    tableView.endUpdates
    updateTitle
  end

  def controller controller, didChangeSection: sectionInfo, atIndex: sectionIndex, forChangeType: type
    case type
    when NSFetchedResultsChangeInsert
      tableView.insertSections(NSIndexSet.indexSetWithIndex(sectionIndex),
                               withRowAnimation: UITableViewRowAnimationFade)
    when NSFetchedResultsChangeDelete
      tableView.deleteSections(NSIndexSet.indexSetWithIndex(sectionIndex),
                               withRowAnimation: UITableViewRowAnimationFade)
    end
  end

  def controller controller, didChangeObject: anObject, atIndexPath: indexPath, forChangeType: type, newIndexPath: newIndexPath
    case type
    when NSFetchedResultsChangeInsert
      tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation: UITableViewRowAnimationFade)
    when NSFetchedResultsChangeDelete
      tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimationFade)
    when NSFetchedResultsChangeUpdate
      configureCell(tableView.cellForRowAtIndexPath(indexPath), atIndexPath: indexPath)
    when NSFetchedResultsChangeMove
      tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimationFade)
      tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation: UITableViewRowAnimationBottom)
    end
  end


  #
  # Action Button
  #

  def actionButtonPressed
    sheet = UIActionSheet.alloc.initWithTitle(
      "Data Manipulation Actions",
      delegate: self,
      cancelButtonTitle: "Cancel",
      destructiveButtonTitle: "Empty Data Directory",
      otherButtonTitles: "Hammer Data Directory", nil)
    sheet.showInView(view.window)
  end

  def actionSheet actionSheet, clickedButtonAtIndex: buttonIndex
    case buttonIndex
    when 0
      hammer.emptyFileSystem
    when 1
      hammer.hammerFileSystem
    end
  end

  def hammer
    @hammer ||= Hammer.new(doc.url.path)
  end


  #
  # Adding a new journal entry
  #

  def addButtonPressed
    alert = UIAlertView.alloc.initWithTitle(
      "New Entry",
      message: nil,
      delegate: self,
      cancelButtonTitle: "Cancel",
      otherButtonTitles: "Save",
      nil)
    alert.alertViewStyle = UIAlertViewStylePlainTextInput
    alert.show
  end

  def alertView alertView, didDismissWithButtonIndex: buttonIndex
    return if buttonIndex == 0   # Bail out if cancel was tapped

    text = alertView.textFieldAtIndex(0).text

    entry = JournalEntry.insertNewInContext(doc.context)
    entry.content = alertView.textFieldAtIndex(0).text
    entry.timestamp = NSDate.date

    doc.save!
  end


  #
  # Setup Methods
  #

  def setupNavBarButtons
    item = UIBarButtonItem.alloc.initWithBarButtonSystemItem(
      UIBarButtonSystemItemAdd,
      target: self,
      action: 'addButtonPressed')
    navigationItem.leftBarButtonItem = item
    item = UIBarButtonItem.alloc.initWithBarButtonSystemItem(
      UIBarButtonSystemItemAction,
      target: self,
      action: 'actionButtonPressed')
    navigationItem.rightBarButtonItem = item
  end

  def updateTitle
    self.title = "Entries (#{fetchedResultsController.fetchedObjects.count})"
  end

end

