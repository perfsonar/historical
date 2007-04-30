import java.io.IOException;
import java.io.File;
import java.util.ArrayList;
import java.lang.String;
import javax.xml.transform.*;
import javax.xml.transform.stream.*;

public class Convert {

  private Convert() {}

  public static void main(String argv[]) {
    if (argv.length == 2) {
      transform(argv[0], argv[1]);
    } else {
      System.err.println("Usage: Convert source.xml style.xsl > output.dot");
    }
    return;
  }

  public static void transform(String sourceID, String xslID) {
    try {
      TransformerFactory factory = TransformerFactory.newInstance();
      Transformer transformer = factory.newTemplates(new StreamSource(new File(xslID))).newTransformer();

      File sourceFile = new File(sourceID);
      transformer.transform(new StreamSource(sourceFile), new StreamResult(System.out));
    } catch (Exception err) {
      System.out.println(err.toString());
      err.printStackTrace();
    }
    return;
  }
}
