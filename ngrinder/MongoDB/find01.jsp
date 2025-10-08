<%@ page session="false" %>
<%@ page import="java.sql.*" %>
<%@ page import="javax.naming.InitialContext, javax.naming.NamingException" %>
<%@ page import="javax.naming.Context" %>
<%@ page import="com.mongodb.client.*" %>
<%@ page import="org.bson.Document" %>
<%@ page import="org.bson.conversions.Bson" %>
<%@ page import="java.util.Random" %>
<%@ page import="java.util.ArrayList" %>
<%@ page import="java.util.List" %>

<%@ page import="static com.mongodb.client.model.Filters.*" %>
<%@ page import="static com.mongodb.client.model.Sorts.*" %>

<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <title>find test</title>
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
    Bson projection = new Document().append("_id", 0);

    // Get random "k"
    int k = random.nextInt(1000000) + 1;
    Document result = collection.find(eq("k", k)).projection(projection).first();
%>
    <h3>k : <%=k%></h3>
    <h5><%=result.toJson()%></h5>
<%
  } catch (NamingException e) {
      e.printStackTrace();
      out.println("Error: " + e.getMessage());
  }
%>
  </p>
</body>
</html>
