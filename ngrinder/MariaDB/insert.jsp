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
    random.setSeed(System.nanoTime());
    int idx = random.nextInt(tableCount) + 1;
    if(log == true) System.out.println("idx = " + idx);
    //String query = "insert into sbtest" + idx + " values(sbtest" + idx + "_seq.nextval,"  + "?,?,?)";
    String query = "insert into sbtest" + idx + " values(?,?,?,?)";
    String id = String.valueOf(System.nanoTime());

    conn = ds.getConnection();
    if(log == true) System.out.println("connected");
    
    pstmt = conn.prepareStatement(query);
    pstmt.setString(1,id);
    pstmt.setInt(2,k);
    pstmt.setString(3,c);
    pstmt.setString(4,pad);
    
    pstmt.executeUpdate();
    
    if(log == true) System.out.println("sucess insert");
     
    result = "sucess";
  }catch(Exception e){

    e.printStackTrace();
    result = "fail";

  }finally{
    try{pstmt.close();} catch (Exception ignored){}
    try {conn.close();} catch (Exception ignored) {}
	}

  out.println(result);
%>
