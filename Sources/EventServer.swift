import Foundation
import Network

final class EventServer {
    private let listener: NWListener
    private weak var model: AppModel?
    private let queue = DispatchQueue(label: "vibe-island.event-server")

    init?(model: AppModel, port: UInt16 = 47831) {
        self.model = model
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        do {
            self.listener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            return nil
        }
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = self.parseRequest(from: nextBuffer) {
                self.process(request: request, on: connection)
                return
            }

            if isComplete || error != nil {
                self.respond(status: "400 Bad Request", body: "bad request", on: connection)
                return
            }

            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func parseRequest(from data: Data) -> (method: String, path: String, body: Data)? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        let contentLength = lines
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "0") }
            ?? 0

        let bodyStart = headerRange.upperBound
        let body = data.suffix(from: bodyStart)
        guard body.count >= contentLength else { return nil }

        return (method, path, Data(body.prefix(contentLength)))
    }

    private func process(request: (method: String, path: String, body: Data), on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            respond(status: "200 OK", body: "{\"ok\":true}", contentType: "application/json", on: connection)

        case ("POST", "/event"):
            do {
                let payload = try JSONDecoder().decode(PiEventPayload.self, from: request.body)
                Task { @MainActor [weak self] in
                    self?.model?.apply(payload)
                }
                respond(status: "200 OK", body: "{\"ok\":true}", contentType: "application/json", on: connection)
            } catch {
                respond(status: "400 Bad Request", body: "invalid json", on: connection)
            }

        default:
            respond(status: "404 Not Found", body: "not found", on: connection)
        }
    }

    private func respond(status: String, body: String, contentType: String = "text/plain", on connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
