<%@ page session="false" %>
<%@ page import="java.sql.*" %>
<%@ page import="javax.naming.InitialContext, javax.naming.NamingException" %>
<%@ page import="javax.naming.Context" %>
<%@ page import="com.mongodb.client.*" %>
<%@ page import="org.bson.Document" %>
<%@ page import="org.bson.conversions.Bson" %>
<%@ page import="java.util.Random" %>

<%@ page import="static com.mongodb.client.model.Sorts.*" %>

<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <title>insert test</title>
</head>
<body>
  <p>
<%!
// Define Global variable
  MongoClient mongoClient = null;
  MongoDatabase database = null;
%>

<%
  Context context = new InitialContext();
  Random random = new Random();

  try {
    if (mongoClient == null) {
      mongoClient = (MongoClient)context.lookup("java:comp/env/mongodb/MyMongoClient");
    }
    if (database == null) {
      database = mongoClient.getDatabase("db01");
    }
    MongoCollection<Document> collection = database.getCollection("loadtest");

    int k, num1, num2;
    String str1, str2;

    // find max of k
    //Bson projection = new Document().append("_id", 0).append("k", 1);
    //Bson sort = orderBy(descending("k"));
    //MongoCursor<Document> cursor = collection.find().projection(projection).sort(sort).limit(1).iterator();

    // If collection is not null, "k" is next of max of "k".
    //if (cursor.hasNext()) {
    //  Document doc = cursor.next();
    //  k = (Integer)doc.get("k") + 1;
    //}
    // If collection is null, k=1.
    //else {
    //  k = 1;
    //}
    k = random.nextInt(100000) + 1000000;

    // c
    String c = "";
    for (int i=0; i<10; i++) {
      num1 = random.nextInt(90000) + 10000;
      num2 = random.nextInt(90000) + 10000;
      str1 = Integer.toString(num1);
      str2 = Integer.toString(num2);
      if (i == 0) {
        c = str1 + str2;
        continue;
      }
      c = c + "-" + str1 + str2;
    }

    // pad
    String pad = "";
    for (int i=0; i<5; i++) {
      num1 = random.nextInt(90000) + 10000;
      num2 = random.nextInt(90000) + 10000;
      str1 = Integer.toString(num1);
      str2 = Integer.toString(num2);
      if (i == 0) {
        pad = str1 + str2;
        continue;
      }
      pad = pad + "-" + str1 + str2;
    }

%>
    <h5>k : <%=k%></h5>
    <h5>c : <%=c%></h5>
    <h5>pad : <%=pad%></h5>
<%
    // insert
    collection.insertOne(new Document().append("k", k).append("c", c).append("pad", pad));

  } catch (NamingException e) {
      e.printStackTrace();
      out.println("Error: " + e.getMessage());
  }
%>
  </p>
</body>
</html>
