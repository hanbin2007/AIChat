//
//  BillingPersistence.swift
//  AIChat Watch App
//
//  Caches the relay-issued device key (`rk_*`), the last seen account
//  status, and the catalog/metering policy so the watch can render
//  balance + plan list while offline. Pure key/value over two
//  singleton rows — no streams, no observation; ViewModels poll on
//  appearance.
//

import Foundation
import SwiftData

actor BillingPersistence {
    private let context: ModelContext
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        // Reuse the relay encoder/decoder so dates round-trip in the
        // same ISO8601 format the wire uses.
        self.decoder = RelayJSON.makeDecoder()
        self.encoder = RelayJSON.makeEncoder()
    }

    // MARK: - Account / device key

    func loadAccountSnapshot() throws -> CachedAccountSnapshot? {
        let entity = try fetchAccountRow()
        guard let entity else { return nil }
        let status: RelayAccountStatusResponse?
        if let data = entity.accountStatusData {
            status = try? decoder.decode(RelayAccountStatusResponse.self, from: data)
        } else {
            status = nil
        }
        return CachedAccountSnapshot(
            keyValue: entity.keyValue,
            accountStatus: status,
            lastRefreshedAt: entity.lastRefreshedAt
        )
    }

    func saveAccountStatus(_ status: RelayAccountStatusResponse, refreshedAt: Date = Date()) throws {
        let entity = try fetchAccountRow() ?? insertAccountRow()
        entity.accountStatusData = try encoder.encode(status)
        entity.lastRefreshedAt = refreshedAt
        try context.save()
    }

    func saveDeviceKey(_ keyValue: String?) throws {
        let entity = try fetchAccountRow() ?? insertAccountRow()
        entity.keyValue = keyValue
        try context.save()
    }

    func clearAccountCache() throws {
        let entity = try fetchAccountRow()
        guard let entity else { return }
        context.delete(entity)
        try context.save()
    }

    // MARK: - Catalog / metering policy

    func loadCatalog() throws -> CachedCatalogSnapshot? {
        let entity = try fetchCatalogRow()
        guard let entity, let data = entity.catalogData else { return nil }
        let catalog = try? decoder.decode(RelayCatalogResponse.self, from: data)
        guard let catalog else { return nil }
        return CachedCatalogSnapshot(
            catalog: catalog,
            lastRefreshedAt: entity.lastRefreshedAt
        )
    }

    func saveCatalog(_ catalog: RelayCatalogResponse, refreshedAt: Date = Date()) throws {
        let entity = try fetchCatalogRow() ?? insertCatalogRow()
        entity.catalogData = try encoder.encode(catalog)
        entity.lastRefreshedAt = refreshedAt
        try context.save()
    }

    func clearCatalogCache() throws {
        let entity = try fetchCatalogRow()
        guard let entity else { return }
        context.delete(entity)
        try context.save()
    }

    // MARK: - Helpers

    private func fetchAccountRow() throws -> RelayAccountCacheEntity? {
        let key = "primary"
        let descriptor = FetchDescriptor<RelayAccountCacheEntity>(
            predicate: #Predicate { $0.key == key }
        )
        return try context.fetch(descriptor).first
    }

    private func insertAccountRow() -> RelayAccountCacheEntity {
        let entity = RelayAccountCacheEntity()
        context.insert(entity)
        return entity
    }

    private func fetchCatalogRow() throws -> BillingPolicyCacheEntity? {
        let key = "primary"
        let descriptor = FetchDescriptor<BillingPolicyCacheEntity>(
            predicate: #Predicate { $0.key == key }
        )
        return try context.fetch(descriptor).first
    }

    private func insertCatalogRow() -> BillingPolicyCacheEntity {
        let entity = BillingPolicyCacheEntity()
        context.insert(entity)
        return entity
    }
}

struct CachedAccountSnapshot: Sendable, Equatable {
    var keyValue: String?
    var accountStatus: RelayAccountStatusResponse?
    var lastRefreshedAt: Date?
}

struct CachedCatalogSnapshot: Sendable, Equatable {
    var catalog: RelayCatalogResponse
    var lastRefreshedAt: Date?
}
