import Foundation

actor TextVariantSyncService {
    static let shared = TextVariantSyncService()

    // MARK: - Remote Sync

    func syncToRemote(variant: TextVariant, userId: UUID) async {
        guard let client = SupabaseManager.shared.client else { return }

        do {
            // Upsert the variant record
            let variantRow: [String: String] = [
                "id": variant.id.uuidString,
                "user_id": userId.uuidString,
                "document_id": variant.documentId.uuidString,
                "unit_id": variant.unitID,
                "kind": variant.kind.rawValue,
                "name": variant.name,
                "instructions": variant.instructions ?? "",
                "status": variant.status.rawValue
            ]

            try await client.from("text_variants")
                .upsert(variantRow)
                .execute()

            // Upsert chunks
            let chunkRows: [[String: String]] = variant.chunks.map { chunk in
                [
                    "variant_id": variant.id.uuidString,
                    "segment_id": chunk.segmentID,
                    "unit_id": chunk.unitID,
                    "transformed_text": chunk.transformedText,
                    "status": chunk.status.rawValue
                ]
            }

            if !chunkRows.isEmpty {
                try await client.from("text_variant_chunks")
                    .upsert(chunkRows)
                    .execute()
            }
        } catch {
            print("[TextVariantSyncService] Failed to sync variant to remote: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote Fetch

    func fetchFromRemote(documentId: UUID, userId: UUID) async -> [TextVariant]? {
        guard let client = SupabaseManager.shared.client else { return nil }

        struct VariantRow: Decodable {
            let id: UUID
            let document_id: UUID
            let unit_id: String
            let kind: String
            let name: String
            let instructions: String?
            let status: String
            let created_at: String?
            let updated_at: String?
        }

        struct ChunkRow: Decodable {
            let variant_id: UUID
            let segment_id: String
            let unit_id: String
            let transformed_text: String
            let status: String
        }

        do {
            let variantRows: [VariantRow] = try await client.from("text_variants")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("document_id", value: documentId.uuidString)
                .execute()
                .value

            guard !variantRows.isEmpty else { return nil }

            let variantIds = variantRows.map { $0.id.uuidString }
            let chunkRows: [ChunkRow] = try await client.from("text_variant_chunks")
                .select()
                .in("variant_id", values: variantIds)
                .execute()
                .value

            let chunksByVariant = Dictionary(grouping: chunkRows) { $0.variant_id }

            let variants: [TextVariant] = variantRows.compactMap { row in
                guard let kind = TextVariantKind(rawValue: row.kind),
                      let status = TextVariantStatus(rawValue: row.status) else { return nil }

                let chunks = (chunksByVariant[row.id] ?? []).compactMap { chunkRow -> TextVariantChunk? in
                    guard let chunkStatus = TextVariantStatus(rawValue: chunkRow.status) else { return nil }
                    return TextVariantChunk(
                        segmentID: chunkRow.segment_id,
                        unitID: chunkRow.unit_id,
                        transformedText: chunkRow.transformed_text,
                        status: chunkStatus
                    )
                }

                return TextVariant(
                    id: row.id,
                    documentId: row.document_id,
                    unitID: row.unit_id,
                    name: row.name,
                    kind: kind,
                    instructions: row.instructions,
                    chunks: chunks,
                    status: status
                )
            }

            return variants.isEmpty ? nil : variants
        } catch {
            print("[TextVariantSyncService] Failed to fetch from remote: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cache Eviction

    func evictStaleLocalCache(library: [LibraryItem], threshold: TimeInterval = 30 * 86400) async {
        let cutoff = Date().addingTimeInterval(-threshold)
        for item in library {
            if let lastOpened = item.lastOpenedAt, lastOpened < cutoff {
                try? await TextVariantStoreActor.shared.delete(documentId: item.documentId)
            }
        }
    }
}
