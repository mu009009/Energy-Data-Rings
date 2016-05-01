import java.util.Collections;
import java.util.Comparator;
// These variables are placed outside of setup() and draw() so that they can be accessed by both functions
PowerDB pdb; // the database connection object
CoordConverter CC; // LatLong <-> Screen conversion utility
double current_time; // Current time to display
double start_time, end_time; // Time range
int day = 1;
int month = 1;
int year = 2014;
int wheelCount = 0;
float zoomSize = 0.5;
int colorkeyX = 1050;
int textcolorkeyX = 1105;
Building selected = null;
double screen_centerX = 0;
double screen_cneterY = 0;

int screenWidth = 1280;
int screenHeight = 1024;

Site Sitesmatch = null;
String current_building_name;
double [] locationX = new double [55];
double [] locationY = new double [55];
double [] locationX2 = new double [55];
double [] locationY2 = new double [55];

float [] iarc = new float [55];
float [] narc = new float [55];
color [] arccolor = new color [55];

int BuildingNumCount = 0;
Site currentBuildingSite = null;
int FalseCount = 0;
int [] FalseBID = new int [55];
double [] SiteValue = new double [55];
Site selected_site = null;

boolean menu_opened = false;
float menu_x, menu_y;
float linex, liney;
List<Site> menu_sites;

boolean previousMousePressed = false;
boolean mouseClicked;

String SiteName = null;

int timecount = 0;
int mouseLock = 0;
int timekey = 0;
int timelock = 0;

int angleMark[] = new int[55];

int mousePreviousX = 0;
int mousePreviousY = 0;
int mouseJudgeX = 0;
int mouseJudgeY = 0;
int mousePreviousCount = 0;
int draglock = 0;

double totalValue = 0;

int frame = 1;

int moveX = 100;

PVector drag_start = null;
boolean mouseRelease = false;
PVector last_dragged_offset = new PVector(0, 0);

List<Site> sorted_sites;

void setup() {
  // Set up the sketch window
  size(screenWidth, screenHeight);

  // Create a new power database interfact and connect to the server
  pdb = new PowerDB();
  pdb.connect();
  pdb.usePreloader(false);

  // Create a coordinate converter using the preset NEU coordinates
  CC = new CoordConverter(NEU_CENTER, NEU_ZOOM);

  // Select start and end times in the format M/D/Y
  start_time = MakeTimestamp(1, 1, 2014);
  end_time = MakeTimestamp(2, 1, 2014);

  // Start the time index at the beginning
  current_time = start_time;

  CC.zoom = 0.5;

  sorted_sites = pdb.getAllSites();
  sortSitesByBuildingUsageType(sorted_sites);
}

// For each frame...
void draw() {
  // Clear the screen
  //background(175, 215, 237);
  background(255, 255, 255);


  mouseClicked = mousePressed && !previousMousePressed;
  mouseRelease = !mousePressed && previousMousePressed && (last_dragged_offset.magSq() < 200);
 
  // Get the ParallelMeasurement at the given time
  // snapTimestamp ensures that we only request a measurement at a valid timestamp; i.e., one that occurs at a 15-minute interval 
  // ParallelMeasurement current_pm = pdb.getParallelMeasurementAt(snapTimestamp(current_time));

  ParallelStatistics current_ps = pdb.getParallelStatisticsBetweenRange(snapTimestamp(current_time), snapTimestamp(current_time)+offsetTime(1, 0, 0));

  // Convert the current time to a DateTime object for easier access
  // Here we use current_pm.timestamp instead of current_time because we want to display 
  // the time of the actual data we recieved, which may be slightly different from what we asked for.
  DateTime current_datetime = TimestampToDateTime(current_time);
  //fill(0);
  // Use .toString() as a shortcut to display the date and time in an easier-to-read format
  //println(current_datetime.toString());

  fill(0);
  //text(TimestampToDateTime(current_time).toString(), 570, 980);222222222222222222222222222

  double total_usage = 0;
  // For each building in the building cache...
  // ( .values() is needed to get the list of associated entries from a hash map)

  int s = 0;

  for (Site current_site : pdb.getAllSites ()) {
    // ...test if measurement data is available for the current site in the specified measurement set 
    if ((current_ps.dataAvailableForSite(current_site))) {
      //if(current_site.name.equals(""))
      //If it is available, store the value for the current site
      //double value = current_pm.getValueForSite(current_site);
      SiteStatistics stats = current_ps.getStatisticsForSite(current_site);
      double value = stats.mean;
      //int bid = current_pm.getBuildingBid(current_site);

      SiteValue[current_site.sID] = value; 
      s = s+1;

      // Store the corresponding building for the site
      Building current_building = pdb.getBuildingFromSite(current_site);

      // Store the geographic centroid of the building as a PDBPoint containing LatLong coordinates
      PDBPoint geo_location = current_building.centroid;

      // Convert this to a PDBPoint holding screen coordinates
      PDBPoint screen_location = CC.LatLongToScreen(geo_location);

      // Accumulate the total usage
      total_usage += value;

      // Set the dot radius to be proportional to the sqrt of the value so that area will be linearly proportional
      float dot_size = sqrt((float)value) * 1.5;

      // Color the ellipse based on power usage
      noStroke();
      //fill(255, (float)value * 0.1, 0, 128);
      fill(255, (float)value * 0.1, 0);
      // Draw an ellipse at the centroid with area proportional to power usage
      // Note that PDBPoint fields must be cast to float first to work with Processing.
      //if(bid == 2)
      //{
      //ellipse((float)screen_location.x, (float)screen_location.y, dot_size, dot_size);
      //}
    }
  }

  //fill(175,215,237); 
  //arc(640, 512, 500, 500, -PI, PI);

  for (Building current_building : pdb.getAllBuildings ()) {
    //Building my_current_building = pdb.getBuildingBy("Name", "Curry Student Center");
    fill(32);
    stroke(64);
    // ...get the outline and draw it using the coordinate converter specified above
    if ((current_building.outline.isMouseOverMap(CC) && (!menu_opened))&&(!clickonButton())) {
      if (current_building.primary_use.equals("Library/Classroom"))
      {
        fill(84, 115, 135);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Classroom/Admin."))
      {
        fill(255, 66, 93);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Athletic Facility"))
      {
        fill(175, 18, 88);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Administrative"))
      {
        fill(98, 65, 24);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Student Services"))
      {
        fill(244, 222, 41);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Research/Classroom"))
      {
        fill(85, 170, 173);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Research"))
      {
        fill(205, 201, 125);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Residence Facility/Academic"))
      {
        fill(217, 104, 49);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Classroom"))
      {
        fill(23, 44, 60);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Classroom/Library"))
      {
        fill(84, 115, 135);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Residence Facility"))
      {
        //a kind of green;
        fill(174, 221, 129);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Mechanical Facility"))
      {
        fill(219, 207, 202);
        current_building.outline.drawOnMap(CC);
      } else if (current_building.primary_use.equals("Residence Facility/Academic"))
      {
        fill(217, 104, 49);
        current_building.outline.drawOnMap(CC);
      } else
      {
        fill(229, 190, 157);
        current_building.outline.drawOnMap(CC);
      }      
      if (mouseRelease/*(mouseButton == LEFT)&&(!menu_opened)*/) {


        timecount = 1;
        timelock = 1;

        current_building.outline.drawOnMap(CC);
        selected = current_building;

        linex = mouseX; 
        liney = mouseY;
        menu_x = mouseX; 
        menu_y = mouseY;
        menu_sites = pdb.getAllSitesWhere(Selector.equals(Site.BID_FIELD, selected.bID));
        if (menu_sites.size() > 1)
        {
          menu_opened = true;
          previousMousePressed = false;
        } else
        {
          menu_opened = false;
          selected_site = menu_sites.get(0);
        }
        //fill(255,255,255);
        //arc(640, 512, 700, 700, iarc[selected.bID], narc[selected.bID], PIE);


        /*for (Site current_site : pdb.getAllSites ())
         {
         if(current_site.bID == current_building.bID)
         {
         current_building_name = current_site.name;
         }
         }*/

        if (selected_site!=null)
        {
          /*fill(250,250,250);
           text(SiteName,linex-35,liney-5);*/
          SiteName = selected_site.name;
        }

        // set click building to the center of the screen.
        CC.screen_center.set(screenWidth/2, screenHeight/2);
        CC.latlon_center = current_building.outline.getCenter();
      }
    } else {

      /*if (timecount == 1)
       {
       //timecount = 1;
       
       if (selected_site!=null)
       {
       fill(250, 250, 250);
       text(selected_site.name, linex-35, liney-5);
       }
       }*/

      fill(151, 151, 151, 100);
      current_building.outline.drawOnMap(CC);
    }


    //pdb.getSiteWhere

    //println(dist((float)current_building.centroid.x,(float)current_building.centroid.y,640,512)+" "+current_building.bID);
    /*if(dist((float)current_building.centroid.x,(float)current_building.centroid.y,640,512)<30)
     {
     //fill(151,151,151,255);
     selected = current_building;
     }*/

    //my_current_building.outline.draw(CC);
    if (current_building.outline.isMouseOverMap(CC) /*&& (selected == null)*/) 
    {
      for (Site current_site : pdb.getAllSites ())
      {
        if (current_site.bID == current_building.bID)
        {
          current_building_name = current_site.name;
        }
      }

      if (selected_site!=null)
      {
        fill(250, 250, 250);
        //text(selected_site.name,mouseX-35,mouseY-5);
      }
    }
  }

  //noFill();
  //ellipse(640,512,30,30);

  /*fill(100);
   noFill();
   rect( 0, 0, 400, 300);
   if (selected != null) {
   if (selected.outline.isMouseOverCenteredAt(160, 160, 180)) {
   fill(32, 32, 90);
   } else {
   fill(64);
   }
   selected.outline.drawCenteredAt(160, 160, 180);
   }*/

  float i = 0.0;
  float n = 1;
  int numi = 0;
  BuildingNumCount = 0;
  FalseCount = 0;

  if (total_usage != 0)
  {



    for (Site current_site : sorted_sites) {
      angleMark[current_site.sID] = (int)i;
      if ((current_ps.dataAvailableForSite(current_site))) {
        //if(current_site.name.equals(""))
        //If it is available, store the value for the current site


          locationX[BuildingNumCount] = (640+350*cos(2*PI-2*PI*i));
        locationY[BuildingNumCount] = (512-350*sin(2*PI-2*PI*(i)));


        BuildingNumCount += 1;
        //println(BuildingNumCount);
        SiteStatistics stats = current_ps.getStatisticsForSite(current_site);
        double value = stats.mean;

        Building current_building = pdb.getBuildingFromSite(current_site);

        n = (float)(value/total_usage);

        //println(n);
        stroke(10);
        if (current_building.primary_use.equals("Library/Classroom"))
        {
          arccolor[current_site.sID] = color(84, 115, 135);
          fill(84, 115, 135);
        } else if (current_building.primary_use.equals("Classroom/Admin."))
        {
          arccolor[current_site.sID] = color(255, 66, 93);
          fill(255, 66, 93);
        } else if (current_building.primary_use.equals("Athletic Facility"))
        {
          arccolor[current_site.sID] = color(175, 18, 88);
          fill(175, 18, 88);
        } else if (current_building.primary_use.equals("Administrative"))
        {
          arccolor[current_site.sID] = color(98, 65, 24);
          fill(98, 65, 24);
        } else if (current_building.primary_use.equals("Student Services"))
        {
          arccolor[current_site.sID] = color(244, 222, 41);
          fill(244, 222, 41);
        } else if (current_building.primary_use.equals("Research/Classroom"))
        {
          arccolor[current_site.sID] = color(85, 170, 173);
          fill(85, 170, 173);
        } else if (current_building.primary_use.equals("Research"))
        {
          arccolor[current_site.sID] = color(205, 201, 125);
          fill(205, 201, 125);
        } else if (current_building.primary_use.equals("Residence Facility/Academic"))
        {
          arccolor[current_site.sID] = color(217, 104, 49);
          fill(217, 104, 49);
        } else if (current_building.primary_use.equals("Classroom"))
        {
          arccolor[current_site.sID] = color(23, 44, 60);
          fill(23, 44, 60);
        } else if (current_building.primary_use.equals("Classroom/Library"))
        {
          arccolor[current_site.sID] = color(84, 115, 135);
          fill(84, 115, 135);
        } else if (current_building.primary_use.equals("Residence Facility"))
        {
          //a kind of green;
          arccolor[current_site.sID] = color(174, 221, 129);
          fill(174, 221, 129);
        } else if (current_building.primary_use.equals("Mechanical Facility"))
        {
          arccolor[current_site.sID] = color(219, 207, 202);
          fill(219, 207, 202);
        } else if (current_building.primary_use.equals("Residence Facility/Academic"))
        {
          arccolor[current_site.sID] = color(217, 104, 49);
          fill(217, 104, 49);
        } else
        {
          arccolor[current_site.sID] = color(229, 190, 157);
          fill(229, 190, 157);
        }
        //arc(640, 512, 700, 700, 2.0*PI*i, 2.0*PI*(i+n), PIE);
        iarc[current_site.sID] = 2.0*PI*i;
        narc[current_site.sID] = 2.0*PI*(i+n);
        numi = numi + 1;
        //locationX2[BuildingNumCount] = (640+350*cos(2*PI-2*PI*(i+n)));
        //locationY2[BuildingNumCount] = (512-350*sin(2*PI-2*PI*(i+n)));

        annulus(640, 512, 2.0*PI*i, 2.0*PI*(i+n), 250, 350);
        i += n;
        //currentBuildingSite = current_site;
        //println(i);
        if (SiteName != null)
        {
          fill(250, 250, 250);
          //text(SiteName,linex-35,liney-5);
        }
      } else
      {
        FalseBID[FalseCount] = current_site.bID;
        FalseCount = FalseCount + 1;
      }
    }

    fill(0);
    // text(TimestampToDateTime(current_pm.timestamp).toString(), 570, 1000);11111111111111111111111

    // Create an accumulator for the total power usage

    // For each site in the database...
    //Site my_current_site = pdb.getSiteBy("bID",10)
    //Site current_site = (Site) pdb.getAllSites().get(26);
    //Site current_site = pdb.getSiteBy("sID",31);
  }

  // Increment the index to get the next set of measurements
  // The "1" can be changed to higher numbers to move through the data faster, albeit skipping entries
  // The use of the % operator makes index "wrap around" to zero when it reaches p_measures.size(), ensuring
  // that index's value is always within 0 and (p_measures.size()-1)
  if (timelock == 0) 
  {
    if (frameCount % frame == 0) 
    {
      current_time += offsetTime(1, 0, 0);//(frameCount % 60) / 60.0 * MEASUREMENT_INTERVAL * 4.0 * 24.0;
      
      timekey = timekey + 1;
    
      if (timekey>23)
      {
        timekey = 0;
      }
    }
  } 
  else if (selected_site!=null)
  {
    // current_time = current_time;
    noStroke();
    fill(arccolor[selected_site.sID], 150);
    selected.outline.drawOnMap(CC);
    arc(640, 512, 700, 700, iarc[selected_site.sID], narc[selected_site.sID], PIE);
    fill(0);

    textSize(20);
    text(selected_site.name, screenWidth/2+5, screenHeight/2-45);

    textSize(14);
    text((float)SiteValue[selected_site.sID]+"  KW·H", screenWidth/2+5, screenHeight/2-25);
    text(((float)SiteValue[selected_site.sID]/((float)total_usage)*100)+"%", screenWidth/2+5, screenHeight/2-5);

    strokeWeight(1);
    textSize(12);
  }

  // Create a rectangle proportional to the total energy usage
  //fill(255, (float)total_usage * 0.005, 0, 128); 22222222222222222222222222222222222222
  //rect(10.0, height, 10.0, height - (float)total_usage * 0.025);

  // Show the time elapsed by representing the current index as a fraction of the screen
  // p_measures.size() provides the total number of measurments, so  ((float)index / (float)p_measures.size()) provides
  // the fraction of the total set that is currently being shown.
  fill(0, 0, 255);
  //rect(0, 0, width * ((float)(current_time - start_time) / (float)(start_time - end_time)), 10);

  //println(locationX[1]+" "+locationY[1]);

  fill(0);
  String Datetime = current_datetime.toString();
  for (int st=0; st<Datetime.length ()-10; st++)
  {
    text(Datetime.charAt(st), 260+st*10, 892);
  }

  //control of menu for sites.    
  if (menu_opened) {
    /*if (menu_sites.size() == 1) {
     selected_site = menu_sites.get(0);
     menu_opened = false;
     }*/
    boolean on_menu = false;
    for (int l = 0; l < menu_sites.size (); l++) {
      menu_x = 640; 
      menu_y = 512;
      if (l==0)
      {
        selected_site = menu_sites.get(0);
      }
      Site draw_site = menu_sites.get(l);
      if (draw_site.equals(selected_site)) {
        fill(150);
      } else {
        fill(100);
      }

      if ((mouseX > menu_x) && (mouseX < menu_x + 250) &&
        (mouseY > menu_y + l * 20) && (mouseY < menu_y  + l * 20 + 20)) {
        on_menu = true;
        fill(130);
        if (mouseRelease) {
          selected_site = draw_site;
          menu_opened = false;
        }
      }

      rect(menu_x, menu_y  + l * 20, 250, 20);
      fill(0);
      text(draw_site.name, menu_x + 10, menu_y  + l * 20 + 15);
    }

    if (dist(mouseX, mouseY, menu_x, menu_y) < 10) {
      on_menu = true;
    }

    /*if (mouseClicked && !on_menu) {
     menu_opened = false;
     }*/
  }

  if (mouseButton == RIGHT)
  {
    selected = null;
    selected_site = null;
    menu_opened = false;
    //current_building.outline.drawOnMap(CC);
    timecount = 0;
    SiteName = null;
    mouseLock = 0;
    timelock = 0;
  }

  timelineX(265, 910);
  timelineHourpart(timekey, 265, 910);

  if ((mouseClicked && clickonButton()) &&! menu_opened)
  {
    if((mouseY>877)&&mouseY<897)
    {
      if ((mouseX>885)&&(mouseX<935))
      {
        if (frame < 5)
        {
          frame = frame + 1;
        }   
        else
        {
          frame = 5;
        }
      }
      else if ((mouseX>950)&&(mouseX<1000))
      {
        if (timelock == 0)
        {
          timelock = 1;
          selected_site = null;
        }   
        else
        {
          timelock = 0;
        }
      }
      else if ((mouseX>1015)&&(mouseX<1065))
      {
        if (frame > 1 )
        {
          frame = frame - 1;
        } 
        else
        {
          frame = 1;
        }
      }
    }
  }

  /*if (current_building.outline.isPointOverMap(width/2, height/2, CC)) 
   {
   center_building = current_building;
   }*/

  drawRectKey();
  timeControlRect(timelock);
  Title();
  textSize(12);
  previousMousePressed = mousePressed;
  strokeWeight(1);
  stroke(0);
}

void mouseWheel(MouseEvent event)
{
  if (dist(mouseX, mouseY, 640, 512)<250) {
    float e = -event.getCount();
    if (e>0)
    {
      wheelCount = wheelCount + 1;
    } else
    {
      wheelCount = wheelCount - 1;
    }

    zoomSize = zoomSize + (float)wheelCount/10;

    if (zoomSize<0.3)
    {
      zoomSize = 0.3;
      wheelCount = 0;
    } else if (zoomSize > 3)
    {
      zoomSize = 3;
      wheelCount = 0;
    }

    CC.zoom = zoomSize;
    //println(wheelCount);
    //println(zoomSize);
  }
}

void mousePressed() {
  drag_start = new PVector(mouseX, mouseY);
  selected_site = null;
  //timelock = 1;
  
  if(mouseLock == 1)
  {
    //selected_site = null;
    menu_opened = false;
    mouseLock = 0;
  }
  
  if(mousePreviousCount != 0)
  {
    mousePreviousCount = 0;
  }
  
  draglock = 0;
}

void mouseDragged()
{
    CC.screen_center.x += mouseX - pmouseX;
    CC.screen_center.y += mouseY - pmouseY;

    double centerX = CC.screen_center.x;
    double centerY = CC.screen_center.y;
    
    selected_site = null;
    menu_opened = false;
    mouseLock = 1;
    timelock = 0;
    
    //Building Select Part
     for (Building current_building : pdb.getAllBuildings ())
     {
       if ((current_building.outline.isPointOverMap(width/2, height/2, CC))&&(current_building.outline.isMouseOverMap(CC))/*(dist(mouseX,mouseY,width/2, height/2)<=30)*/)
       {
         if(CC.zoom>=1.5)
         {
           // set click building to the center of the screen.
           timelock = 1;
           
           CC.screen_center.set(screenWidth/2, screenHeight/2);
           CC.latlon_center = current_building.outline.getCenter();
              
           selected = current_building;

           linex = mouseX; 
           liney = mouseY;
           menu_x = mouseX; 
           menu_y = mouseY;
           menu_sites = pdb.getAllSitesWhere(Selector.equals(Site.BID_FIELD, selected.bID));
           if(menu_sites.size() > 1)
           {
             menu_opened = true;
             previousMousePressed = false;
           }
           else
           {
             menu_opened = false;
             selected_site = menu_sites.get(0);
           }
           return ;
         }
       }
    }
}

void mouseReleased()
{

  last_dragged_offset.set(mouseX - drag_start.x, mouseY - drag_start.y);
  drag_start = null;
  
}
/*
// get the screen coordinates of the center of the building;
 PDBPoint center = CC.LatLongToScreen(building.outline.getCenter());
 
 cetner.x, center.y
 
 // get the lat-long coordinates of thecenter of the screen
 CC.ScreenToLatLong(new PBPOint(width/2, height/2));
 
 // center the map at the selected building;
 CC.latlon_center = building.outline.getCenter()
 
 
 */

/*void annulus(float x, float y, float start, float end, float inner, float outer) {
 float a = min(start, end);
 float b = max(start, end);
 int numSteps = 20;
 float inc = (end - start)/numSteps;
 beginShape();
 vertex(x + outer * cos(a), y + outer * sin(a));
 curveVertex(x + outer * cos(a), y + outer * sin(a));
 for (float theta = a; theta < b; theta += inc) {
 curveVertex(x + outer * cos(theta), y + outer * sin(theta));
 }
 curveVertex(x + outer * cos(b), y + outer * sin(b));
 vertex(x + outer * cos(b), y + outer * sin(b));
 vertex(x + inner * cos(b), y + inner * sin(b));
 curveVertex(x + inner * cos(b), y + inner * sin(b));
 for (float theta = b; theta > a; theta -= inc) {
 curveVertex(x + inner * cos(theta), y + inner * sin(theta));
 }
 curveVertex(x + inner * cos(a), y + inner * sin(a));
 vertex(x + inner * cos(a), y + inner * sin(a));
 vertex(x + outer * cos(a), y + outer * sin(a));
 endShape();
 }*/

public void sortSitesByBuildingUsageType(List<Site> sites) {
  class SiteComparator implements Comparator<Site> {
    public int compare(Site s1, Site s2) {
      return pdb.getBuildingFromSite(s1).primary_use.compareTo(pdb.getBuildingFromSite(s2).primary_use);
    }
  }
  Collections.sort(sites, new SiteComparator());
}

public void drawRectKey()
{
  noStroke();
  fill(84, 115, 135);
  rect(100 + moveX, 950, 30, 15);
  fill(0);
  textSize(12);
  text("Library/Classroom", 135 + moveX, 962);

  fill(255, 66, 93);
  rect(255 + moveX, 950, 30, 15);
  fill(0);
  textSize(12);
  text("Classroom/Admin", 290 + moveX, 962);

  fill(175, 18, 88);
  rect(410 + moveX, 950, 30, 15);
  fill(0);
  textSize(12);
  text("Athletic Facility", 445 + moveX, 962);

  fill(98, 65, 24);
  rect(565 + moveX, 950, 30, 15);
  fill(0);
  textSize(12);
  text("Administrative", 600 + moveX, 962);

  fill(244, 222, 41);
  rect(720 + moveX, 950, 30, 15);
  fill(0);
  textSize(12);
  text("Student Services", 755 + moveX, 962);

  fill(85, 170, 173);
  rect(875 + moveX, 950, 30, 15);
  fill(0);
  textSize(12);
  text("Research/Classroom", 910 + moveX, 962);

  fill(205, 201, 125);
  rect(100 + moveX, 980, 30, 15);
  fill(0);
  textSize(12);
  text("Research", 135 + moveX, 992);

  fill(23, 44, 60);
  rect(255 + moveX, 980, 30, 15);
  fill(0);
  textSize(12);
  text("Classroom", 290 + moveX, 992);

  fill(174, 221, 129);
  rect(410 + moveX, 980, 30, 15);
  fill(0);
  textSize(12);
  text("Residence Facility", 445 + moveX, 992);      

  fill(219, 207, 202);
  rect(565 + moveX, 980, 30, 15);
  fill(0);
  textSize(12);
  text("Mechanical Facility", 600 + moveX, 992);

  fill(217, 104, 49);
  rect(720 + moveX, 980, 30, 15);
  fill(0);
  textSize(12);
  text("Residence Facility/Academic", 755 + moveX, 992);
}

public void timelineHourpart(int time, int x, int y)
{
  fill(238, 233, 233);
  rect(x-10+time*800/23, y-8, 10, 16);
}

void timelineX(int x, int y)
{
  textSize(12);
  stroke(238, 233, 233);
  strokeWeight(5);
  line(x, y, x+800, y);
  for (int i=0; i<24; i++)
  {
    fill(0);
    if (i<=9)
    {
      text(i, x+i*800/23-8, y+20);
    } else
    {
      text(i, x+i*800/23-12, y+20);
    }
  }
  strokeWeight(1);
}

void timeControlRect(int timelock)
{
  noFill();
  stroke(120, 120, 120);
  rect(885, 877, 50, 20, 7);
  //fill(120,120,120);
  text("slow", 898, 891);

  noFill();
  stroke(120, 120, 120);
  rect(950, 877, 50, 20, 7);
  if (timelock == 0)
  {
    text("stop", 963, 891);
  } else if (timelock == 1)
  {
    text("start", 963, 891);
  }

  noFill();
  stroke(120, 120, 120);
  rect(1015, 877, 50, 20, 7);
  //fill(120,120,120);
  text("fast", 1028, 891);
}

void Title()
{
  textSize(32);
  //fill(120,120,120);
  text("Energy Data Rings", 20, 60);
  textSize(12);
  text("This project is to show the percentage of electricity", 22, 85);
  text("consumption for each building to the whole school.", 22, 105);
}

boolean clickonButton()
{
  if (((mouseX>885)&&(mouseY<935))&&((mouseY>877)&&(mouseY<897)))
  {
    return true;
  } else if ((((mouseX>950)&&(mouseX<1000)))&&((mouseY>877)&&(mouseY<897)))
  {
    return true;
  } else if ((((mouseX>1015)&&(mouseX<1065)))&&((mouseY>877)&&(mouseY<897)))
  {
    return true;
  } else
  {
    return false;
  }
}

