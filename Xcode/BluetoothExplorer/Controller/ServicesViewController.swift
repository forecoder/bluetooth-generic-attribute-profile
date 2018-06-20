//
//  PeripheralDetailViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/20/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import Bluetooth
import GATT

final class ServicesViewController: TableViewController {
    
    // MARK: - IB Outlets
    
    @IBOutlet private(set) var activityIndicatorBarButtonItem: UIBarButtonItem!
    
    // MARK: - Properties
    
    public var peripheral: Peripheral!
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        reloadData()
    }
    
    // MARK: - Actions
    
    @IBAction func pullToRefresh(_ sender: UIRefreshControl) {
        
        reloadData()
    }
    
    // MARK: - Methods
    
    func configureView() {
        
        guard isViewLoaded else { return }
        
        guard let identifier = self.peripheral?.identifier,
            let managedObject = try! PeripheralManagedObject.find(identifier, in: DeviceStore.shared.managedObjectContext)
            else { assertionFailure(); return }
        
        self.title = managedObject.scanData.advertisementData.localName ?? identifier.uuidString
    }
    
    func reloadData() {
        
        guard let peripheral = self.peripheral
            else { fatalError("View controller not configured") }
        
        configureView()
        
        let isRefreshing = self.refreshControl?.isRefreshing ?? false
        let showActivity = isRefreshing == false
        performActivity(showActivity: showActivity, { try DeviceStore.shared.discoverServices(for: peripheral) },
                        completion: { (viewController, _) in viewController.endRefreshing() })
    }
    
    override func newFetchedResultController() -> NSFetchedResultsController<NSManagedObject> {
        
        guard let identifier = self.peripheral?.identifier
            else { fatalError("View controller not configured") }
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "%K == %@",
                                    #keyPath(ServiceManagedObject.peripheral.identifier),
                                    identifier.uuidString as NSString)
        
        let sort = [NSSortDescriptor(key: #keyPath(ServiceManagedObject.uuid), ascending: true)]
        let context = DeviceStore.shared.managedObjectContext
        let fetchedResultsController = NSFetchedResultsController(ServiceManagedObject.self,
                                                                  delegate: self,
                                                                  predicate: predicate,
                                                                  sortDescriptors: sort,
                                                                  context: context)
        fetchedResultsController.fetchRequest.fetchBatchSize = 30
        
        return fetchedResultsController
    }
    
    private subscript (indexPath: IndexPath) -> ServiceManagedObject {
        
        guard let managedObject = self.fetchedResultsController?.object(at: indexPath) as? ServiceManagedObject
            else { fatalError("Invalid type") }
        
        return managedObject
    }
    
    private func configure(cell: UITableViewCell, at indexPath: IndexPath) {
        
        let managedObject = self[indexPath]
        
        let service = CentralManager.Service(managedObject: managedObject)
        
        cell.textLabel?.text = service.uuid.description
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ServiceCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
}

// MARK: - ActivityIndicatorViewController

extension ServicesViewController: ActivityIndicatorViewController {
    
    func showActivity() {
        
        self.view.endEditing(true)
        
        self.activityIndicatorBarButtonItem.customView?.alpha = 1.0
    }
    
    func hideActivity(animated: Bool = true) {
        
        let duration: TimeInterval = animated ? 0.5 : 0.0
        
        UIView.animate(withDuration: duration) { [weak self] in
            
            self?.activityIndicatorBarButtonItem.customView?.alpha = 0.0
        }
    }
}