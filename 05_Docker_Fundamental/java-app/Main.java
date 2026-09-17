// Hello World web app using the JDK's built-in com.sun.net.httpserver,
// so no Maven, Gradle or external jar is required.
// Dhruv Davda - 24BCS10203

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class Main {

    private static final int PORT =
        Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", PORT), 0);

        server.createContext("/", exchange -> {
            String host = InetAddress.getLocalHost().getHostName();
            String page = """
                <!DOCTYPE html>
                <html lang="en">
                <head><meta charset="utf-8"><title>Hello World - Java</title></head>
                <body style="font-family: system-ui, sans-serif; text-align:center; padding-top:80px;">
                  <h1>Hello World from Java</h1>
                  <p>Dhruv Davda &middot; 24BCS10203 &middot; Group A</p>
                  <p>JDK %s inside container %s</p>
                </body>
                </html>
                """.formatted(System.getProperty("java.version"), host);

            byte[] body = page.getBytes(StandardCharsets.UTF_8);
            System.out.println(exchange.getRequestMethod() + " " + exchange.getRequestURI());
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        });

        server.setExecutor(null);   // default single-threaded executor is fine here
        System.out.println("listening on 0.0.0.0:" + PORT);
        server.start();
    }
}
