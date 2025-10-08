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
  <title>find range test</title>
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

    // Get random value
    int random_value = random.nextInt(1000000) + 1;
    int nLimit = 100;
    Bson filter = and(gt("k", random_value), lt("k", random_value+nLimit), gt("a", random_value), lt("a", random_value+nLimit));

    Document result;
    MongoCursor<Document> cursor = collection.find(filter).projection(projection).limit(nLimit).iterator();
    while(cursor.hasNext()) {
      result = cursor.next();
%>
    <h5><%=random_value%> ~ <%=random_value+nLimit%></h5>
    <h5><%=result.toJson()%></h5>
<%
    }
  } catch (NamingException e) {
      e.printStackTrace();
      out.println("Error: " + e.getMessage());
  }
%>
  </p>
</body>
</html>
