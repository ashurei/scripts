<%@ page session="false" %>
<%@ page import="java.sql.*" %>
<%@ page import="javax.naming.*" %>
<%@ page import="javax.sql.*" %>
<%@ page import="javax.rmi.*" %>
<%@ page import="java.util.Random" %>

<%!
   DataSource ds = null;
%>

<%
  boolean log = false;
  String result = null;

  Connection conn = null;
  PreparedStatement pstmt = null;
  ResultSet rs = null;

  int tableCount = 10;

  try {
    Random random = new Random();
    random.setSeed(System.currentTimeMillis());
    int idx = random.nextInt(tableCount) + 1;
    if(log == true) System.out.println("idx = " + idx);

    String query = "select c from sbtest" + idx + " where id = ?";

    if(ds == null){
      Context initContext = new InitialContext();
      Context envContext  = (Context)initContext.lookup("java:/comp/env");
      ds = (DataSource)envContext.lookup("jdbc/mariadb");
    }

    Random random2 = new Random();
    random2.setSeed(System.currentTimeMillis());
    int id = random2.nextInt(999999) + 1;
    if(log == true) System.out.println("random2 id = " + id);

    conn = ds.getConnection();
    if(log == true) System.out.println("connected");

    pstmt = conn.prepareStatement(query);
    pstmt.setInt(1,id);
    rs = pstmt.executeQuery();

    /*
    String c = null;
    while (rs.next()) {
      c = rs.getString(1);
      if(log == true) System.out.println("c = " + c);
    }*/
    rs.close();
    pstmt.close();

    result = "success";
  }
  catch(Exception e){
    e.printStackTrace();
    result = "fail";
  }
  finally {
    try {conn.close();} catch (Exception ignored) {}
  }

  out.println(result);
%>
