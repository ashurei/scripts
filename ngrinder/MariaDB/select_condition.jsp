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
  int cond = 1200;

  try {
    Random random = new Random();
    random.setSeed(System.currentTimeMillis());
    int idx = random.nextInt(tableCount) + 1;
    int idx2 = 1;
    
    if(idx == 10) idx2 = 1;
    else idx2 = idx + 1;
    
    if(log == true){ 
      System.out.println("idx = " + idx);
      System.out.println("idx2 = " + idx2);
    }

    String query = "select *  from sbtest" + idx + " a, sbtest" + idx2 + " b where a.id < ? and b.id < ?";
  
    if(ds == null){
      Context initContext = new InitialContext();
      Context envContext  = (Context)initContext.lookup("java:/comp/env");
      ds = (DataSource)envContext.lookup("jdbc/mariadb");
    }

    conn = ds.getConnection();
    if(log == true) System.out.println("connected");
       
    //pstmt = conn.prepareStatement(query,ResultSet.TYPE_SCROLL_INSENSITIVE,ResultSet.CONCUR_READ_ONLY);
    pstmt = conn.prepareStatement(query);
  
    pstmt.setInt(1,cond);
    pstmt.setInt(2,cond);
    pstmt.setFetchSize(1);
    
    rs = pstmt.executeQuery();
  
    int count = 0;
    while (rs.next()) {
      count = rs.getInt(1);
    }

    if(log == true) System.out.println("row count = " + count);
	
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
