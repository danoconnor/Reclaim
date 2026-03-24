//
//  ContentView.swift
//  Reclaim
//
//  Created by Dan O'Connor on 11/8/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if DEBUG
        if DemoDataProvider.isUITestMode {
            let services = DemoDataProvider.createDemoServices()
            MainView(
                photoLibraryService: services.photoLibraryService,
                oneDriveService: services.oneDriveService,
                comparisonService: services.comparisonService,
                deletionService: services.deletionService,
                storeService: services.storeService
            )
        } else {
            MainView()
        }
        #else
        MainView()
        #endif
    }
}

#Preview {
    ContentView()
}
