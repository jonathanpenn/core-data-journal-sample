class Document

  attr_reader :context, :coordinator, :model

  def initialize
    Dispatch.once { registerCustomIncrementalStore }
    setupCoreDataStack
  end

  def url
    return @url if @url

    # Read where the data directory should be. This is overridable in the
    # Rakefile so you can specify a different folder on your Mac when running
    # in the simulator.

    path = NSBundle.mainBundle.infoDictionary["APP_DataDirectory"]

    if path == "default"
      @url = NSFileManager.defaultManager.URLsForDirectory(
        NSDocumentDirectory,
        inDomains: NSUserDomainMask)[0]
      @url = @url.URLByAppendingPathComponent("Journal")
    else
      puts "Storing data in #{path}"
      @url = NSURL.fileURLWithPath(path)
    end
  end

  def save!
    # Using `performBlockAndWait` so that you can call save! on any thread or
    # queue and it will "do the right thing" and make sure the root context
    # is saved on the thread or queue that it belongs to.

    error_ptr = Pointer.new(:object)
    success = false
    context.performBlockAndWait -> {
      success = context.save(error_ptr)
    }
    raise ErrorWrapper.new(error_ptr[0]) if !success
  end


  #
  # Setup Methods
  #

  def registerCustomIncrementalStore
      NSPersistentStoreCoordinator.registerStoreClass(
        MyIncrementalStore,
        forStoreType: MyIncrementalStore.name)
  end

  def setupCoreDataStack
    setUpManagedObjectModel
    setUpPersistentStoreCoordinator
    setUpManagedObjectContext
    tellCustomStoreAboutTheRootContext
  end

  def setUpManagedObjectModel
    @model = NSManagedObjectModel.mergedModelFromBundles(nil)
  end

  def setUpPersistentStoreCoordinator
    @coordinator = NSPersistentStoreCoordinator.alloc.
      initWithManagedObjectModel(model)

    storeType = MyIncrementalStore.name

    # Want to use sqlite? Just use this instead.

    # storeType = NSSQLiteStoreType
    # storeType = NSInMemoryStoreType

    error_ptr = Pointer.new(:object)
    success = coordinator.addPersistentStoreWithType(
      storeType,
      configuration: nil,
      URL: self.url,
      options: nil,
      error: error_ptr)

    raise ErrorWrapper.new(error_ptr[0]) if !success
  end

  def setUpManagedObjectContext
    @context = NSManagedObjectContext.alloc.
      initWithConcurrencyType(NSMainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
  end

  def tellCustomStoreAboutTheRootContext
    # If we're using the custom incremental store, then we want to set the root
    # context on it. It uses the root context to notify the rest of Core Data
    # when files on the disk change underneath it.

    store = coordinator.persistentStores[0]
    if store.type == MyIncrementalStore.name
      store.rootContext = context
    end
  end

end

