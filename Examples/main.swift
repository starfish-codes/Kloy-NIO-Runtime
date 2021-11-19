import Core
import KloyNIORuntime

func simpleService(status: Status = .ok, body: String) -> (Request) -> Response {
    { request in
        Response(status: status, headers: [], version: request.version, body: .init(from: body)!)
    }
}

if #available(macOS 12.0.0, *) {
    let server = Server(
        from: routed(route(.get, "cats") ~> simpleService(body: "All 🐈"))
    )
    
    run(server: server, port: 8003)
} else {
    // Fallback on earlier versions
}

