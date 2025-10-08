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
  int rowCount = 20;

  try {
    Random random = new Random();
    random.setSeed(System.currentTimeMillis());
    int idx = random.nextInt(tableCount) + 1;
    if(log == true) System.out.println("idx = " + idx);
    
    //String query1 = "select max(id) from sbtest" + idx;
    
    String query = "select c from sbtest" + idx + " where id between ? and ?";

    if(ds == null){
      Context initContext = new InitialContext();
      Context envContext  = (Context)initContext.lookup("java:/comp/env");
      ds = (DataSource)envContext.lookup("jdbc/mariadb");
    }

    conn = ds.getConnection();
    if(log == true) System.out.println("connected");
    
    Random random2 = new Random();
    random2.setSeed(System.currentTimeMillis());
    int id1 = random2.nextInt(999999) + 1;
    if(log == true) System.out.println("random2 id1 = " + id1);
        
    int id2 = id1 - rowCount;
    if(id2 < 1) id2 = 1;
    if(log == true) System.out.println("random3 id2 = " + id2);
    
    //pstmt = conn.prepareStatement(query,ResultSet.TYPE_SCROLL_INSENSITIVE,ResultSet.CONCUR_READ_ONLY);
    pstmt = conn.prepareStatement(query);
  
    pstmt.setInt(1,id2);
    pstmt.setInt(2,id1);
    pstmt.setFetchSize(1);
    
    rs = pstmt.executeQuery();
  
    //rs.last();
    //if(log == true) System.out.println("row count = " + rs.getRow()); 
    //rs.beforeFirst();
  
    rs.close();
    pstmt.close();
        
    result = "sucess";
  }catch(Exception e){

    e.printStackTrace();
    result = "fail";

  }finally {
    
   // try{pstmt.close();} catch (Exception ignored){}
    try {conn.close();} catch (Exception ignored) {}
	}

  out.println(result);
%>
