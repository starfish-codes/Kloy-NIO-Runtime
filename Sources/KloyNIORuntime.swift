import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Core
import NIO
import NIOHTTP1
import NIOHTTPCompression

@available(macOS 12.0.0, *)
public func run(server: Server, eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount), port: Int = 8080) {
    do {
        let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Set up the Server Chanel
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(reuseAddrOpt, value: 1)
            // Set up closure that will be used to initialise child channels (when a connection is accepted to our server)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    // Add handler
                    let handlers: [ChannelHandler] = [KloyHandler(for: server)]
                    return channel.pipeline.addHandlers(handlers, position: .last)
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(reuseAddrOpt, value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let host = "0.0.0.0"
        let serverChannel = try bootstrap.bind(host: host, port: port).wait()
        print("Listening on \(host):\(port)...")
        try serverChannel.closeFuture.wait()
        try eventLoopGroup.syncShutdownGracefully()
    } catch {
        fatalError(error.localizedDescription)
    }
}

@available(macOS 12.0.0, *)
private final class KloyHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart // HTTPPart<HTTPRequestHead, ByteBuffer>
    let server: Server
    var kloyMethod: Core.HTTPMethod?
    var kloyHeaders: [Core.Header]?
    var kloyUri: String?
    var kloyHttpVersion: Core.HTTPVersion?
    var kloyBody: Core.Body?

    init(for server: Server) {
        self.server = server
        self.kloyHeaders = []
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)

        switch reqPart {
        case let .head(header):
            self.kloyMethod = .init(rawValue: header.method.rawValue.lowercased())!
            let headers = header.headers.reduce(into: [:]) { $0[$1.name] = $1.value }
            headers.forEach {
                key, value in
                self.kloyHeaders?.append(.init(name: key, value: value))
            }
            // header.version.
            self.kloyUri = header.uri
            self.kloyHttpVersion = .oneOne
        case var .body(bodyPart):
            guard let bytes = bodyPart.readBytes(length: bodyPart.readableBytes) else{
                return
            }
            
            self.kloyBody = .init(payload: Data(bytes: bytes, count: bytes.count))
                
        case .end:
            guard let method = self.kloyMethod else {
                return
            }
            guard let headers = self.kloyHeaders else {
                return
            }
            guard let uri = self.kloyUri else {
                return
            }
            guard let kloyHttpVersion = self.kloyHttpVersion else {
                return
            }

            var body: Core.Body
            if self.kloyBody == nil {
                body = .empty
            } else {
                body = self.kloyBody!
            }

            let req = Core.Request(method: method, headers: headers, uri: uri, version: kloyHttpVersion, body: body)


            let promise = context.eventLoop.makePromise(of: Core.Response.self)
            promise.completeWithTask {
                
                return await self.server.process(request: req)
            }
            

             promise.futureResult.whenSuccess{ res in
                
                let head = HTTPResponseHead(
                    version: .init(major: 1, minor: 1),
                    status: .init(statusCode: res.status.code),
                    headers: .init(res.headers.map { ($0.name, $0.value) })
                )
                context.channel.write(HTTPServerResponsePart.head(head), promise: nil)

                var buffer = context.channel.allocator.buffer(capacity: res.body.payload.count)
                 buffer.writeBytes(res.body.payload )
                context.channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)

                _ = context.channel.writeAndFlush(HTTPServerResponsePart.end(nil)).flatMap {
                    context.channel.close()
                }
            }
        }
    }
}
