<%@page session="false" %>
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
  
  int tableCount = 10;

  int k = 111111;
  String c = "08566691963-88624912351-16662227201-46648573979-64646226163-77505759394-75470094713-41097360717-15161106334-50535565977";
  String pad = "63188288836-92351140030-06390587585-66802097351-49282961843";

  try {  
    if(ds == null){
      Context initContext = new InitialContext();
      Context envContext  = (Context)initContext.lookup("java:/comp/env");
      ds = (DataSource)envContext.lookup("jdbc/mariadb");
    }

    Random random = new Random();
    random.setSeed(System.currentTimeMillis());
    int idx = random.nextInt(tableCount) + 1;
    if(log == true) System.out.println("idx = " + idx);
    String query = "insert into sbtest" + idx + " (k,c,pad) values(?,?,?)";

    conn = ds.getConnection();
    if(log == true) System.out.println("connected");
    
    pstmt = conn.prepareStatement(query);
    pstmt.setInt(1,k);
    pstmt.setString(2,c);
    pstmt.setString(3,pad);
    
    pstmt.executeUpdate();
    
    if(log == true) System.out.println("success insert");
 
    result = "success";
  } catch(Exception e){
    e.printStackTrace();
    result = "fail";
  } finally {
    try{pstmt.close();} catch (Exception ignored){}
    try {conn.close();} catch (Exception ignored) {}
  }

  out.println(result);
%>
