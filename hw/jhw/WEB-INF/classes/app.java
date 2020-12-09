
import java.io.*;
import java.util.HashMap;
import java.util.Map;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet("/")
public class app extends HttpServlet
{
    private byte   body_huge[] = new byte[1024 * 1024];
    private Map<String, Long>  body_def = new HashMap<>();
    private String data = "Hello, world!\n";
    private Long   min_size = Long.valueOf(data.length());

    public app() {
        byte b[] = data.getBytes();

        for (int i = 0; i < body_huge.length; i++) {
            body_huge[i] = b[i % b.length];
        }

        body_def.put("/",    min_size);
        body_def.put("/1k",  1024L);
        body_def.put("/4k",  1024L * 4);
        body_def.put("/16k", 1024L * 16);
        body_def.put("/64k", 1024L * 64);
        body_def.put("/1m",  1024L * 1024);
    }

    @Override
    public void doGet(HttpServletRequest request, HttpServletResponse response)
        throws IOException, ServletException
    {
        int l = body_def.getOrDefault(request.getServletPath(), min_size).intValue();

        response.setContentLength(l);
        response.setContentType("text/plain");

        response.getOutputStream().write(body_huge, 0, l);
    }
}
