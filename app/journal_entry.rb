class JournalEntry < NSManagedObject

  # attr_accessor :timestamp, :content

  def self.insertNewInContext context
    entity = NSEntityDescription.entityForName(
      "JournalEntry", inManagedObjectContext: context)
    alloc.initWithEntity(entity, insertIntoManagedObjectContext: context)
  end

  def self.fetchRequest
    request = NSFetchRequest.alloc.initWithEntityName("JournalEntry")
    request.sortDescriptors = [
      NSSortDescriptor.sortDescriptorWithKey("timestamp", ascending: false)
    ]
    request
  end

end

