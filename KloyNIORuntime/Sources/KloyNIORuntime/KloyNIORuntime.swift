import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIO
import NIOHTTP1
import NIOHTTPCompression
import Core


    
@available(macOS 12.0.0, *)
public func run(server : Server, baseUrl: URL, eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount), port: Int = 8080){
    do {
      let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
      let bootstrap = ServerBootstrap(group: eventLoopGroup)
        //Set up the Server Chanel
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(reuseAddrOpt, value: 1)
        //Set up closure that will be used to initialise child channels (when a connection is accepted to our server)
        .childChannelInitializer { channel in
          channel.pipeline.configureHTTPServerPipeline().flatMap {
              //Add handler
            let handlers: [ChannelHandler] = [KloyHandler()]
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
private final class KloyHandler: ChannelInboundHandler{
    typealias InboundIn = HTTPServerRequestPart // HTTPPart<HTTPRequestHead, ByteBuffer>
    let server: Server
    var kloyMethod: Core.HTTPMethod
    var kloyHeaders: [Core.Header]
    var kloyUri:String
    var kloyHttpVersion: Core.HTTPVersion
    var request: Core.Request?
    
    init(for server: Server) {
      self.server = server
        self.kloyHeaders = []
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) async {
        let reqPart  = self.unwrapInboundIn(data)
        
        switch reqPart {
        case let .head(header):
            self.kloyMethod = .init(rawValue: header.method.rawValue.lowercased())!
            let headers = header.headers.reduce(into: [:]) { $0[$1.name] = $1.value }
            headers.forEach{
                key, value in
                self.kloyHeaders.append(.init(name: key, value: value))
            }
            //header.version.
            self.kloyUri = header.uri
            self.kloyHttpVersion = .oneOne
        case var .body(bodyPart):
            var data: Data = .init()
            let bytes = bodyPart.readBytes(length: bodyPart.readableBytes)
            
            bytes?.forEach{
                data.append(.init($0))
            }
            self.request = .init(method: self.kloyMethod, headers: self.kloyHeaders, uri: self.kloyUri, version: self.kloyHttpVersion, body: .init(payload: data))
        case .end:
            guard let req = self.request else{
                return
            }
            
            let res = await self.server.process(request: req)
            
            let head = HTTPResponseHead(
              version: .init(major: 1, minor: 1),
              status: .init(statusCode: res.status.rawValue),
              headers: .init(res.headers.map { ($0.name, $0.value) })
            )
            context.channel.write(HTTPServerResponsePart.head(head), promise: nil)

            var buffer = context.channel.allocator.buffer(capacity: res.body.count)
            buffer.writeBytes(res.body)
            context.channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)

            return context.channel.writeAndFlush(HTTPServerResponsePart.end(nil)).flatMap {
              context.channel.close()
            }
        }
        
        
        
        
        //self.server.process(request: )
    }
}

extension HTTPHeaders{
    func all(){
        self.
    }
}
