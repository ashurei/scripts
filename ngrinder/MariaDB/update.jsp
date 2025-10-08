<%@ page session="false" %>
<%@ page import="java.sql.*" %>

<%@ page import="javax.naming.*" %>
<%@ page import="javax.sql.*" %>
<%@ page import="javax.rmi.*" %>
<%@ page import="java.util.Random" %>
<%@ page import="java.lang.*" %>

<%!   
   DataSource ds = null;
%>

<%
  boolean log = false;
  String result = null;
  
  Connection conn = null;
  PreparedStatement pstmt = null;

  int tableCount = 10;

  try {  

    Random random = new Random();
    random.setSeed(System.nanoTime());
    int idx = random.nextInt(tableCount) + 1;
    if(log == true) System.out.println("idx = " + idx);
    
    //String query = "select c from sbtest" + idx + " where id = ?";
    String query = "update sbtest" + idx + " set c = ? where id = ?";
    //String c = "08566691963-88624912351-16662227201-46648573979-64646226163-77505759394-75470094713-41097360717-15161106334-50535565977";
    //String c = "11111111111-11111111111-16662227201-46648573979-64646226163-77505759394-75470094713-41097360717-15161106334-50535565977";
    String c = "";

    // Create random C
    int[] arrC = new int[11];
    int number;
    String tempS;
    Random randomC = new Random();
    for(int i=0; i<10; i++) {
      tempS = "";
      for(int j=0; j<11; j++) {
        randomC.setSeed(System.nanoTime());
        number = randomC.nextInt(10);  
        tempS = tempS + Integer.toString(number);
      }
      c = c + tempS;
      if (i != 9) c = c + "+";
    }
    //out.println(c);
      
    if(ds == null){
      Context initContext = new InitialContext();
      Context envContext  = (Context)initContext.lookup("java:/comp/env");
      ds = (DataSource)envContext.lookup("jdbc/mariadb");
    }

    Random random2 = new Random();
    random2.setSeed(System.nanoTime());
    int id = random2.nextInt(999999) + 1;
    if(log == true) System.out.println("random2 id = " + id);


    conn = ds.getConnection();
    if(log == true) System.out.println("connected");

    pstmt = conn.prepareStatement(query);
    pstmt.setString(1,c);
    pstmt.setInt(2,id);
    pstmt.executeUpdate();
    
    pstmt.close();
    if(log == true) System.out.println("c = " + c);
    
    result = "sucess";
  }catch(Exception e){

    e.printStackTrace();
    result = "fail";

  }finally {

    try {conn.close();} catch (Exception ignored) {}
	}

  out.println(result);
%>
