APCoreDataStackManager is a class that lets you set up a Core Data stack, using a local or ubiquitous persistent store.

Features
--------

- Sets and resets the Core Data stack using a local or ubiquitous persistent store.
- Builds the stack asynchronously, executing a completion handler when the managed object context is ready to use.
- Uses a delegate to handle needed actions.
- Notifies the delegate at the key steps when adding the persistent store.

How to use
----------

The APCoreDataStackManager.h header file should be self-explanatory. Read the demo application source to get an example of a possible implementation.

How does it work?
-----------------

When seeding initial content to iCloud, the manager generates a UUID to use as the persistent store content name. It stores it in a plist configuration file at the root of the ubiquity container.

This file is observed by other instances of the manager to be notified when the ubiquitous store has changed. If a new store has been seeded, and the delegate returns ``YES`` for ``- (BOOL)coreDataStackManagerShouldUseUbiquitousStore:(APCoreDataStackManager *)manager;``, the ``- (void)coreDataStackManagerRequestUbiquitousStoreRefresh:(APCoreDataStackManager *)manager;`` method of the delegate is called. Otherwise, the delegate is told to reset the stack using the local persistent store with ``- (void)coreDataStackManagerRequestLocalStoreRefresh:(APCoreDataStackManager *)manager;``.

When you application becomes active, and since the user can log out of iCloud when it is running, it should check for iCloud's availability using ``- (void)checkUbiquitousStorageAvailability;``. This method checks that it can access the ubiquity container, and that it can read the plist configuration file.

License Agreement
-----------------

The source code is released under the following BSD license:

> Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

> Redistributions of source code must retain attribution of Axel Péju as the original author of the source code, this list of conditions and the following disclaimer.

> Redistributions in binary form must reproduce attribution of Axel Péju as the original author of the source code, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

> THIS SOFTWARE IS PROVIDED BY AXEL PEJU ”AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL AXEL PEJU OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.