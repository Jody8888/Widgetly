//
//  ContentView.swift
//  Widgetly
//
//  Created by Jody on 2026/3/2.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
           
            Text("Widgetly")
                .fontWeight(.heavy)
                .font(.system(size: 50))
                .padding(.top, -50)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
