import com.mongodb.BasicDBObject;
import com.mongodb.BulkWriteOperation;
import com.mongodb.BulkWriteResult;
import com.mongodb.Cursor;
import com.mongodb.DB;
import com.mongodb.DBCollection;
import com.mongodb.DBCursor;
import com.mongodb.DBObject;
import com.mongodb.MongoClient;
import com.mongodb.MapReduceOutput;
import com.mongodb.MapReduceCommand;
import com.mongodb.ParallelScanOptions;

import java.util.List;
import java.util.Calendar;
import java.util.GregorianCalendar;
import java.util.TimeZone;


PDBPoint NEU_CENTER=new PDBPoint(-71.08921, 42.33874);
double NEU_ZOOM=80000.0;
double MEASUREMENT_INTERVAL=15.0*60.0;

String MapSerialStats = "function() {" +
"emit(this.sID,{x:this.value,count:1," +
"sum:this.value,min:this.value,max:this.value," + 
"variance:0,mean:0,M2:0});};";
String MapParallelStats = "function () {" +
"for (var key in this) {" +
"if (parseInt(key) == key) {" +
"emit(parseInt(key), {" +
"x: this[key]," +
"count: 1," +
"sum: this[key]," +
"min: this[key]," +
"max: this[key]," +
"variance: 0," +
"mean: 0," +
"M2: 0})}}};";

String ReduceStats = "function(key,values) {" +
"var reduced=values[0];var " + 
"delta = 0;for (var i = 1; i < values.length; i++) " + 
"{var value = values[i];reduced.count += value.count;" + 
"reduced.sum += value.x;reduced.min = Math.min(reduced.min, " + 
"value.min);reduced.max = Math.max(reduced.max, value.max);" + 
"delta = value.x - reduced.mean;reduced.mean += delta / " + 
"reduced.count;reduced.M2 += delta * (value.x - reduced.mean);" + 
"}reduced.variance = reduced.M2/(reduced.count - 1);" + 
"return reduced;};";
String makeMonthMatch(int month) {
  return "function() { " +
    "var asDate = new Date(this.timestamp * 1000);" +
    "return asDate.getUTCMonth() == " + month + ";};";
}
String makeDayMatch(int day) {
  return "function() { " +
    "var asDate = new Date(this.timestamp * 1000);" +
    "return asDate.getUTCDate() == " + day + ";};";
}
String makeWeekdayMatch(int weekday) {
  return "function() { " +
    "var asDate = new Date(this.timestamp * 1000);" +
    "return asDate.getUTCDay() == " + weekday + ";};";
}



Iterable<DBObject> performMapReduce(DBCollection collection, String mapfunc, String reducefunc, SelectorList selector) {
  return collection.mapReduce(mapfunc, reducefunc, "temp_stats", MapReduceCommand.OutputType.INLINE, selector.getQuery()).results();
}

class PowerDB {
  private MongoClient mongoClient;
  private DB db;
  private DBCollection sitedb;
  private DBCollection buildingdb;
  private DBCollection measurementdb_serial;
  private DBCollection measurementdb_parallel;
  private boolean connected;
  private boolean warn_null;
  private boolean use_preload;
  private HashMap<Site, Building> building_cache;

  PowerDB() {
    connected = false;
    warn_null = true;
    use_preload = true;
    building_cache = new HashMap<Site, Building>();
  }

  // Database management

  public void connect() {
    if (connected) {
      println("[WARN]: Database already connected.");
    } else {

      try {
        println("[NOTE]: Connecting to database...");
        mongoClient = new MongoClient("localhost", 27016);
        db = mongoClient.getDB("pudb");
        sitedb = db.getCollection("sitedb");
        buildingdb = db.getCollection("buildingdb");
        measurementdb_serial = db.getCollection("measurementdb_serial");
        measurementdb_parallel = db.getCollection("measurementdb_parallel");
        println("[NOTE]: Connection complete.");
        println("[NOTE]: Checking indicies...");
        measurementdb_serial.createIndex(new BasicDBObject(SerialMeasurement.TIMESTAMP_FIELD, 1));
        measurementdb_serial.createIndex(new BasicDBObject(SerialMeasurement.TIMESTAMP_FIELD, -1));
        measurementdb_serial.createIndex(new BasicDBObject(SerialMeasurement.SID_FIELD, 1));
        measurementdb_serial.createIndex(new BasicDBObject(SerialMeasurement.SID_FIELD, -1));
        measurementdb_parallel.createIndex(new BasicDBObject(ParallelMeasurement.TIMESTAMP_FIELD, 1));
        measurementdb_parallel.createIndex(new BasicDBObject(ParallelMeasurement.TIMESTAMP_FIELD, -1));
        connected = true;
        println("[NOTE]: Indexing complete.");
      } 
      catch (java.net.UnknownHostException e) {
        println("[ERROR]: Cannot reach data server. Ensure server is running with port 27016");
      }
      if (this.use_preload) {
        this.preloadAllSitesAndBuildings();
      }
    }
  }

  public void warnIfNull(boolean val) {
    warn_null = val;
  }

  public void usePreloader(boolean val) {
    if (val && connected) {
      this.preloadAllSitesAndBuildings();
    }
    use_preload = val;
  }


  // Site - Building Cache

  private void preloadAllSitesAndBuildings() {
    println("[NOTE]: Preloading all sites and buildings...");
    if (this.building_cache.size() == 0) {
      this.use_preload = false;
      List<Site> all_sites = this.getAllSites();
      for (Site current_site : all_sites) {

        Building current_building = this.getBuildingFromSite(current_site);
        building_cache.put(current_site, current_building);
      }
      println("[NOTE]: Loaded " + building_cache.keySet().size() + " site-building pairs.");
      this.use_preload = true;
    }
  }

  private List<Building> getAllPreloadedBuildings() {
    if (this.building_cache.size() == 0) {
      println("[ERROR]: Must preload sites and buildings with preloadAllSitesAndBuildings() before accessing.");
      return null;
    } else {
      return new ArrayList(this.building_cache.values());
    }
  }

  private List<Site> getAllPreloadedSites() {
    if (this.building_cache.size() == 0) {
      println("[ERROR]: Must preload sites and buildings with preloadAllSitesAndBuildings() before accessing.");
      return null;
    } else {
      return new ArrayList(this.building_cache.keySet());
    }
  }

  private Building getPreloadedBuildingForSite(Site site) {
    if (this.building_cache.size() == 0) {
      println("[ERROR]: Must preload sites and buildings with preloadAllSitesAndBuildings() before accessing.");
      return null;
    } else {
      return building_cache.get(site);
    }
  }


  // Site operations

  public List<Integer> getAllSiteIDs() {
    DBCursor cursor = sitedb.find(new BasicDBObject(), 
    new BasicDBObject("sID", 1))
      .sort(new BasicDBObject("sID", 1));

    List<Integer> reslist = new ArrayList<Integer>();
    try {
      while (cursor.hasNext ()) {
        reslist.add((Integer) cursor.next().get("sID"));
      }
    } 
    finally {
      cursor.close();
    }

    return reslist;
  }

  public List<Site> getAllSites() {
    if (this.use_preload) {
      return this.getAllPreloadedSites();
    } else {
      DBCursor cursor = sitedb.find(new BasicDBObject())
        .sort(new BasicDBObject("sID", 1));

      List<Site> reslist = new ArrayList<Site>();
      try {
        while (cursor.hasNext ()) {
          reslist.add(new Site((BasicDBObject) cursor.next()));
        }
      } 
      finally {
        cursor.close();
      }

      return reslist;
    }
  }

  public Site getSiteBy(String field, Object val) {
    BasicDBObject res = (BasicDBObject) sitedb.findOne(new BasicDBObject(field, val));
    if (warn_null && (res == null)) {
      println("[WARN] Site query for {" + field + " : '" + val + "'} returned 0 results.");
      return null;
    } else {
      try {
        return new Site(res);
      } 
      catch (NullPointerException e) {
        println("[ERROR]: Invalid data retrieved from siteDB");
        return null;
      }
    }
  }

  public List<Site> getAllSitesWhere(SelectorList selector) {
    DBCursor cursor = sitedb.find(selector.getQuery())
      .sort(new BasicDBObject("sID", 1));

    List<Site> reslist = new ArrayList<Site>();
    try {
      while (cursor.hasNext ()) {
        reslist.add(new Site((BasicDBObject) cursor.next()));
      }
    } 
    finally {
      cursor.close();
    }

    return reslist;
  }


  // Building operations

  public List<Integer> getAllBuildingIDs() {
    DBCursor cursor = buildingdb.find(new BasicDBObject(), 
    new BasicDBObject("bID", 1))
      .sort(new BasicDBObject("bID", 1));

    List<Integer> reslist = new ArrayList<Integer>();
    try {
      while (cursor.hasNext ()) {
        reslist.add((Integer) cursor.next().get("bID"));
      }
    } 
    finally {
      cursor.close();
    }

    return reslist;
  }

  public List<Building> getAllBuildings() {
    if (this.use_preload) {
      return this.getAllPreloadedBuildings();
    } else {
      DBCursor cursor = buildingdb.find(new BasicDBObject())
        .sort(new BasicDBObject("bID", 1));

      List<Building> reslist = new ArrayList<Building>();
      try {
        while (cursor.hasNext ()) {
          BasicDBObject q = (BasicDBObject) cursor.next();
          Building b = new Building(q);
          reslist.add(b);
        }
      } 
      finally {
        cursor.close();
      }

      return reslist;
    }
  }

  public Building getBuildingBy(String field, Object val) {
    BasicDBObject res = (BasicDBObject) buildingdb.findOne(new BasicDBObject(field, val));
    if (warn_null && (res == null)) {
      println("[WARN] Building query for {" + field + " : '" + val + "'} returned 0 results.");
      return null;
    } else {
      try {
        return new Building(res);
      } 
      catch (NullPointerException e) {
        println("[ERROR]: Invalid data retrieved from buildingDB");
        return null;
      }
    }
  }

  public List<Building> getAllBuildingsWhere(SelectorList selector) {
    DBCursor cursor = buildingdb.find(selector.getQuery())
      .sort(new BasicDBObject("bID", 1));

    List<Building> reslist = new ArrayList<Building>();
    try {
      while (cursor.hasNext ()) {
        BasicDBObject q = (BasicDBObject) cursor.next();
        Building b = new Building(q);
        reslist.add(b);
      }
    } 
    finally {
      cursor.close();
    }

    return reslist;
  }

  public Building getBuildingFromSite(Site site) {
    if (this.use_preload) {
      return getPreloadedBuildingForSite(site);
    } else {
      return this.getBuildingBy(Building.BID_FIELD, site.bID);
    }
  }

  // Time operations

  public double getMinimumTime() {
    BasicDBObject res = (BasicDBObject) (measurementdb_parallel.find(new BasicDBObject(), 
    new BasicDBObject("timestamp", 1))
      .sort(new BasicDBObject("timestamp", 1))
      .limit(1)
      .one());
    return res.getDouble("timestamp");
  }

  public double getMinimumTimeForSite(int sID) {
    BasicDBObject res = (BasicDBObject) (measurementdb_serial.find(new BasicDBObject("sID", sID), 
    new BasicDBObject("timestamp", 1))
      .sort(new BasicDBObject("timestamp", 1))
      .limit(1)
      .one());
    return res.getDouble("timestamp");
  }

  public double getMinimumTimeForSite(Site site) {
    return this.getMinimumTimeForSite(site.sID);
  }

  public double getMaximumTime() {
    BasicDBObject res = (BasicDBObject) (measurementdb_parallel.find(new BasicDBObject(), 
    new BasicDBObject("timestamp", 1))
      .sort(new BasicDBObject("timestamp", -1))
      .limit(1)
      .one());
    return res.getDouble("timestamp");
  }

  public double getMaximumTimeForSite(int sID) {
    BasicDBObject res = (BasicDBObject) (measurementdb_serial.find(new BasicDBObject("sID", sID), 
    new BasicDBObject("timestamp", 1))
      .sort(new BasicDBObject("timestamp", -1))
      .limit(1)
      .one());
    return res.getDouble("timestamp");
  }

  public double getMaximumTimeForSite(Site site) {
    return this.getMaximumTimeForSite(site.sID);
  }

  // Serial measurement operations

  // per site
  public List<SerialMeasurement> getSerialMeasurementsBy(String field, Object val) {
    DBCursor cursor = measurementdb_serial.find(new BasicDBObject(field, val))
      .sort(new BasicDBObject(SerialMeasurement.TIMESTAMP_FIELD, 1));
    List<SerialMeasurement> reslist = new ArrayList<SerialMeasurement>();
    try {
      for (DBObject row : cursor) {
        reslist.add(new SerialMeasurement((BasicDBObject) row));
      }
    } 
    finally {
      cursor.close();
    }
    return reslist;
  }

  public List<SerialMeasurement> getSerialMeasurementsFromSite(Site site) {
    return getSerialMeasurementsBy(Site.SID_FIELD, site.sID);
  }

  // value ranges
  public List<SerialMeasurement> getSerialMeasurementsWhere(SelectorList selectors) {
    DBCursor cursor = measurementdb_serial.find(selectors.getQuery()).sort(new BasicDBObject(SerialMeasurement.TIMESTAMP_FIELD, 1));
    List<SerialMeasurement> reslist = new ArrayList<SerialMeasurement>();
    try {
      for (DBObject row : cursor) {
        reslist.add(new SerialMeasurement((BasicDBObject) row));
      }
    } 
    finally {
      cursor.close();
    }
    return reslist;
  }

  public List<SerialMeasurement> getSerialMeasurementsFromSiteWhere(Site site, SelectorList selectors) {
    return this.getSerialMeasurementsWhere(Selector.equals(Site.SID_FIELD, site.sID).and(selectors));
  }


  // Parallel measurement operations

    // time point
  public ParallelMeasurement getParallelMeasurementAt(double timestamp) {
    // strange precision errors necessitate searching within a narrow range
    double timestamp_fixed = snapTimestamp(timestamp);
    BasicDBObject query = new BasicDBObject(ParallelMeasurement.TIMESTAMP_FIELD, 
    new BasicDBObject("$gte", (timestamp_fixed - 60.0)).append("$lte", (timestamp_fixed + 60.0)));
    BasicDBObject res = (BasicDBObject) (measurementdb_parallel.findOne(query));

    if (warn_null && (res == null)) {
      println("[WARN]: Parallel Measurement query for {" + timestamp + "} returned 0 results.");
      return null;
    } else {
      try {
        return new ParallelMeasurement(res);
      } 
      catch (NullPointerException e) {
        println("[ERROR]: Invalid data retrieved from measurementDB:parallel");
        return null;
      }
    }
  }

  // time slice
  public List<ParallelMeasurement> getParallelMeasurementsWhere(SelectorList selectors) {
    DBCursor cursor = measurementdb_parallel.find(selectors.getQuery()).sort(new BasicDBObject(ParallelMeasurement.TIMESTAMP_FIELD, 1));
    List<ParallelMeasurement> reslist = new ArrayList<ParallelMeasurement>();
    try {
      for (DBObject row : cursor) {
        reslist.add(new ParallelMeasurement((BasicDBObject) row));
      }
    } 
    finally {
      cursor.close();
      return reslist;
    }
  }


  // aggregation

  public List<SiteStatistics> getHistoricStatisticsForWeekdays(Site site) {
    return null;
  }


  public SiteStatistics getSiteStatisticsBetweenRange(Site site, double start, double end) {
    return this.getSiteStatisticsBetweenRange(site.sID, start, end);
  }

  public SiteStatistics getSiteStatisticsBetweenRange(int sID, double start, double end) {
    Iterable<DBObject> out = performMapReduce(pdb.measurementdb_serial, 
    MapSerialStats, ReduceStats, 
    Selector.equals(SerialMeasurement.SID_FIELD, sID)
      .and(Selector.inRange(SerialMeasurement.TIMESTAMP_FIELD, start, end)));

    if (out.iterator().hasNext()) {
      return new SiteStatistics((BasicDBObject)out.iterator().next());
    } else {
      println("[WARN] No results found for site statistics.");
      return null;
    }
  }

  public SiteStatistics getSiteStatisticsForDay(Site site, double startOfDay) {
    return this.getSiteStatisticsForDay(site.sID, startOfDay);
  }

  public SiteStatistics getSiteStatisticsForDay(int sID, double startOfDay) {
    return this.getSiteStatisticsBetweenRange(sID, startOfDay, startOfDay + 86400.0);
  }


  public ParallelStatistics getParallelStatisticsBetweenRange(double start, double end) {
    Iterable<DBObject> out = performMapReduce(pdb.measurementdb_parallel, 
    MapParallelStats, ReduceStats, 
    Selector.inRange(ParallelMeasurement.TIMESTAMP_FIELD, start, end));

    return new ParallelStatistics(out);
  }

  public ParallelStatistics getParallelStatisticsForDay(double startOfDay) {
    return this.getParallelStatisticsBetweenRange(startOfDay, startOfDay + 86400.0);
  }
}


class SelectorList {
  private BasicDBObject queryList;

  SelectorList(BasicDBObject query) {
    this.queryList = new BasicDBObject();
    this.queryList.putAll((BSONObject) query);
  }

  SelectorList and(SelectorList chain) {
    this.queryList.putAll((BSONObject) chain.queryList); // check that this is the right function
    return this;
  }

  BasicDBObject getQuery() {
    return this.queryList;
  }
}

class SelectorSingleton {
  public SelectorList equals(String _key, Object _value) {
    return new SelectorList(new BasicDBObject(_key, _value));
  }

  public SelectorList lessThan(String _key, Object _value) {
    return new SelectorList(new BasicDBObject(_key, new BasicDBObject("$lte", _value)));
  }

  public SelectorList greaterThan(String _key, Object _value) {
    return new SelectorList(new BasicDBObject(_key, new BasicDBObject("$gte", _value)));
  }

  public SelectorList inRange(String _key, Object _lVal, Object _rVal) {
    return new SelectorList(new BasicDBObject(_key, new BasicDBObject("$gte", _lVal).append("$lte", _rVal)));
  }

  public SelectorList script(String script) {
    return new SelectorList(new BasicDBObject("$where", script));
  }

  public SelectorList matchMonth(int month) {
    return this.script(makeMonthMatch(month));
  }


  public SelectorList matchDay(int day) {
    return this.script(makeDayMatch(day));
  }

  public SelectorList matchWeekday(int weekday) {
    return this.script(makeWeekdayMatch(weekday));
  }
}

SelectorSingleton Selector = new SelectorSingleton();

class SerialMeasurement {
  public static final String TIMESTAMP_FIELD = "timestamp";
  public static final String SID_FIELD = "sID";
  public static final String VALUE_FIELD = "value";

  public double timestamp;
  public int sID;
  public double value;

  SerialMeasurement(double _timestamp, int _sID, double _value) {
    this.timestamp = _timestamp;
    this.sID = _sID;
    this.value = _value;
  }

  SerialMeasurement(BasicDBObject query) {
    this.timestamp = query.getDouble(TIMESTAMP_FIELD);
    this.sID = query.getInt(SID_FIELD);
    this.value = query.getDouble(VALUE_FIELD);
  }

  String toString() {
    return "Measurement Time: " + this.timestamp + ", sID: " + this.sID + ", value: " + value;
  }
}

class ParallelMeasurement {
  public static final String TIMESTAMP_FIELD = "timestamp";

  private BasicDBObject values;
  public double timestamp;

  ParallelMeasurement(BasicDBObject query) {
    this.timestamp = query.getDouble(TIMESTAMP_FIELD);
    this.values = query;
  }

  boolean dataAvailableForSite(int sID) {
    return this.values.get("" + sID) != null;
  }

  boolean dataAvailableForSite(Site site) {
    return this.dataAvailableForSite(site.sID);
  }

  Double getValueForSite(int sID) {
    return this.values.getDouble("" + sID);
  }

  Double getValueForSite(Site site) {
    return this.getValueForSite(site.sID);
  }
}

class Site {
  public static final String SID_FIELD = "sID";
  public static final String NAME_FIELD = "Name";
  public static final String ABBR_FIELD = "Abbreviation";
  public static final String BID_FIELD = "bID";

  public int sID;
  public String name;
  public String abbreviation;
  public int bID;

  Site(BasicDBObject query) throws NullPointerException {
    this.sID = query.getInt(SID_FIELD);
    this.name = query.getString(NAME_FIELD);
    this.abbreviation = query.getString(ABBR_FIELD);
    this.bID = query.getInt(BID_FIELD);
  }

  Site(int _sID, String _name, String _abbr, int _bID) {
    this.sID = _sID;
    this.name = _name;
    this.abbreviation = _abbr;
    this.bID = _bID;
  }

  String toString() {
    return "Site Name: " + this.name + ", Abbr: " + this.abbreviation + ", sID: " + this.sID + ", bID: " + this.bID;
  }

  @Override
    public int hashCode() {
    return sID;
  }

  @Override
    public boolean equals(Object obj) {
    if (!(obj instanceof Site))
      return false;
    if (obj == this)
      return true;
    return this.sID == ((Site)obj).sID;
  }

  public int compareTo(Site other) {
    return new Integer(this.sID).compareTo(other.sID);
  }
}


class SiteStatistics {
  int sID;
  int count;
  double sum;
  double min;
  double max;
  double variance;
  double stddev;
  double mean;

  SiteStatistics(BasicDBObject reduced)  throws NullPointerException {
    this.sID = reduced.getInt("_id");
    BasicDBObject values = (BasicDBObject)reduced.get("value"); 
    this.count = values.getInt("count");
    this.sum = values.getDouble("sum");
    this.min = values.getDouble("min");
    this.max = values.getDouble("max");
    this.variance = values.getDouble("variance");
    this.stddev = sqrt((float)this.variance);
    this.mean = values.getDouble("mean");
  }

  String toString() {
    return "Site: " + this.sID + ", Count: " + this.count + ", Sum: " + this.sum +
      ", Min: " + this.min + ", Max: " + this.max + ", Variance: " + this.variance + ", Stddev:" + this.stddev + ", Mean: " + this.mean;
  }
};

class ParallelStatistics {
  private HashMap<Integer, SiteStatistics> stats_cache;

  ParallelStatistics(Iterable<DBObject> results) {
    stats_cache = new HashMap<Integer, SiteStatistics>();
    for (DBObject result : results) {
      SiteStatistics stat = new SiteStatistics((BasicDBObject)result);
      stats_cache.put(new Integer(stat.sID), stat);
    }
  }

  boolean dataAvailableForSite(Site site) {
    return this.dataAvailableForSite(site.sID);
  }

  boolean dataAvailableForSite(int sID) {
    return this.stats_cache.containsKey(new Integer(sID));
  }


  SiteStatistics getStatisticsForSite(Site site) {
    return this.getStatisticsForSite(site.sID);
  }

  SiteStatistics getStatisticsForSite(int sID) {
    return this.stats_cache.get(new Integer(sID));
  }
}


class Building {
  public static final String BID_FIELD = "bID";
  public static final String USE_FIELD = "Primary Use";
  public static final String FLOORS_FIELD = "Floors";
  public static final String YEAR_FIELD = "Year Acquired";
  public static final String PERIMETER_FIELD = "Perimeter";
  public static final String AREA_FIELD = "Area";
  public static final String FOOTPRINT_FIELD = "Footprint";
  public static final String CENTROID_FIELD = "Centroid";
  public static final String OUTLINE_FIELD = "Outline";

  public int bID;
  public String primary_use;
  public int floors;
  public int year_acquired;
  public double perimeter;
  public double area;
  public double footprint;
  public PDBPoint centroid;
  public PDBOutline outline;

  Building(BasicDBObject query) throws NullPointerException {
    this.bID = query.getInt(BID_FIELD);
    this.primary_use = query.getString(USE_FIELD);
    this.floors = query.getInt(FLOORS_FIELD);
    this.year_acquired = new Integer(query.getString(YEAR_FIELD)); // Int represented as a string in DB
    this.perimeter = query.getDouble(PERIMETER_FIELD);
    this.area = query.getDouble(AREA_FIELD);
    this.footprint = query.getDouble(FOOTPRINT_FIELD);
    this.centroid = new PDBPoint((ArrayList<Double>) query.get(CENTROID_FIELD));
    this.outline = new PDBOutline((ArrayList<ArrayList<Double>>) query.get(OUTLINE_FIELD));
  }

  Building(int _bID, String _primary_use, int _floors, int _years_acquired, 
  double _perimeter, double _area, double _footprint, PDBPoint _centroid, PDBOutline _outline) {
    this.bID = _bID;
    this.primary_use = _primary_use;
    this.floors = _floors;
    this.year_acquired = _years_acquired;
    this.perimeter = _perimeter;
    this.area = _area;
    this.footprint = _footprint;
    this.centroid = _centroid;
    this.outline = _outline;
  }

  String toString() {
    return "Building ID: " + this.bID + ", Centroid: " + this.centroid + ", ...";
  }


  @Override
    public int hashCode() {
    return bID;
  }

  @Override
    public boolean equals(Object obj) {
    if (!(obj instanceof Building))
      return false;
    if (obj == this)
      return true;
    return this.bID == ((Building)obj).bID;
  }

  public int compareTo(Building other) {
    return new Integer(this.bID).compareTo(other.bID);
  }
}

class PDBPoint {

  public double x;
  public double y;

  PDBPoint(ArrayList<Double> from_list) {
    this.x = from_list.get(0);
    this.y = from_list.get(1);
  }

  PDBPoint(PVector from_pvec) {
    this.x = from_pvec.x;
    this.y = from_pvec.y;
  }

  PDBPoint(double _x, double _y) {
    this.x = _x;
    this.y = _y;
  }

  void set(double _x, double _y) {
    this.x = _x;
    this.y = _y;
  }

  PVector asPVector() {
    return new PVector((float) this.x, (float) this.y);
  }

  ArrayList<Double> asList() {
    ArrayList<Double> res = new ArrayList<Double>();
    res.add(new Double(this.x));
    res.add(new Double(this.y));
    return res;
  }

  String toString() {
    return "Point(" + this.x + ", " + this.y + ")";
  }
}

class PDBOutline extends ArrayList<PDBPoint> {
  float minX, minY, maxX, maxY;

  PDBOutline(ArrayList<ArrayList<Double>> from_list) {
    this.clear();
    minX =  99999.0; 
    minY =  99999.0;
    maxX = -99999.0; 
    maxY = -99999.0;
    for (ArrayList<Double> point : from_list) {
      PDBPoint pt = new PDBPoint(point);
      this.add(pt);
      minX = min(minX, (float)pt.x);
      maxX = max(maxX, (float)pt.x);
      minY = min(minY, (float)pt.y);
      maxY = max(maxY, (float)pt.y);
    }
  }

  PDBPoint getCenter() {
    float centroidX = (minX + maxX) * 0.5;
    float centroidY = (minY + maxY) * 0.5;
    return new PDBPoint(centroidX, centroidY);
  }


  void drawCenteredAt(float x, float y, float size) {
    float cSize = max(maxX - minX, maxY - minY);
    float centroidX = (minX + maxX) * 0.5;
    float centroidY = (minY + maxY) * 0.5;
    float scale = size / cSize;
    float px, py;
    beginShape();  
    for (PDBPoint coord : this) {
      px = ((float)coord.x - centroidX) * scale + x;
      py = (-(float)coord.y + centroidY) * scale + y;
      vertex(px, py);
    }
    endShape(CLOSE);
  }


  boolean pointInside(PDBPoint p) {
    boolean oddNodes = false;
    PDBPoint pi;
    PDBPoint pj = this.get(this.size() - 1);
    for (int i = 0; i < this.size (); i++) {
      pi = this.get(i);

      if ((pi.y < p.y && pj.y >= p.y
        || pj.y < p.y && pi.y >= p.y)
        && (pi.x <= p.x || pj.x <= p.x)) {
        oddNodes ^= (pi.x + (p.y - pi.y)/(pj.y - pi.y)*(pj.x - pi.x) < p.x);
      }
      pj = pi;
    }
    return oddNodes;
  }


  boolean isMouseOverCenteredAt(float x, float y, float size) {
    return isPointOverCenteredAt(mouseX, mouseY, x, y, size);
  }

  boolean isPointOverCenteredAt(float px, float py, float x, float y, float size) {
    float cSize = max(maxX - minX, maxY - minY);
    float centroidX = (minX + maxX) * 0.5;
    float centroidY = (minY + maxY) * 0.5;
    float scale = cSize / size;
    //float px, py;

    PDBPoint latlon = new PDBPoint((px - x) * scale + centroidX, (-py + y) * scale + centroidY);
    return pointInside(latlon);
  }

  boolean isMouseOverMap(CoordConverter CC) {
    return isPointOverMap(mouseX, mouseY, CC);
  }

  boolean isPointOverMap(float px, float py, CoordConverter CC) {
    return this.pointInside(CC.ScreenToLatLong(new PDBPoint(px, py)));
  }

  boolean isMouseOverMapCenteredAt(float x, float y, CoordConverter CC) {
    return isPointOverMapCenteredAt(mouseX, mouseY, x, y, CC);
  }

  boolean isPointOverMapCenteredAt(float px, float py, float x, float y, CoordConverter CC) {
    PDBPoint old = CC.screen_center;
    CC.setScreenCenter(x, y);
    boolean res = this.pointInside(CC.ScreenToLatLong(new PDBPoint(px, py)));
    CC.setScreenCenter(old.x, old.y);
    return res;
  }

  void drawOnMap(CoordConverter CC) {
    beginShape();
    for (PDBPoint coord : CC.LatLongToScreen (this)) {
      vertex((float) coord.x, (float) coord.y);
    }
    endShape(CLOSE);
  }

  void drawOnMapCenteredAt(float x, float y, CoordConverter CC) {
    PDBPoint old = CC.screen_center;
    CC.setScreenCenter(x, y); 
    beginShape();
    for (PDBPoint coord : CC.LatLongToScreen (this)) {
      vertex((float) coord.x, (float) coord.y);
    }
    endShape(CLOSE);
    CC.setScreenCenter(old.x, old.y);
  }

  PShape toPShape(CoordConverter CC) {
    PShape s = createShape();
    s.beginShape();
    for (PDBPoint coord : CC.LatLongToScreen (this)) {
      s.vertex((float) coord.x, (float) coord.y);
    }
    s.endShape();
    return s;
  }


  String toString() {
    String res = "Outline [";
    for (PDBPoint coord : this) {
      res += coord + " ";
    }
    return res + "]";
  }
}

class CoordConverter {
  PDBPoint latlon_center;
  PDBPoint screen_center;
  double scale;
  double zoom;

  CoordConverter(PDBPoint _latlon_center, double _scale) {
    this.latlon_center = _latlon_center;
    this.screen_center = new PDBPoint(width / 2, height / 2);
    this.scale = _scale;
    this.zoom = 1.0;
  }

  CoordConverter(PDBPoint _latlon_center, PDBPoint _screen_center, double _scale) {
    this.latlon_center = _latlon_center;
    this.screen_center = _screen_center;
    this.scale = _scale;
    this.zoom = 1.0;
  }

  void setScreenCenter(double x, double y) {
    this.screen_center.x = x;
    this.screen_center.y = y;
  }

  void setZoom(double _zoom) {
    this.zoom = _zoom;
  }

  PDBPoint LatLongToScreen(PDBPoint point) {
    double x, y;
    x = (point.x - latlon_center.x) * scale * zoom + screen_center.x;
    y = -(point.y - latlon_center.y) * scale * zoom + screen_center.y;
    return new PDBPoint(x, y);
  }

  List<PDBPoint> LatLongToScreen(List<PDBPoint> points) {
    List<PDBPoint> res = new ArrayList<PDBPoint>();
    for (PDBPoint point : points) {
      res.add(this.LatLongToScreen(point));
    }
    return res;
  }

  PDBPoint ScreenToLatLong(PDBPoint point) {
    double x, y;
    x = (point.x - screen_center.x) / (scale * zoom) + latlon_center.x;
    y = -(point.y - screen_center.y) / (scale * zoom) + latlon_center.y;
    return new PDBPoint(x, y);
  }

  List<PDBPoint> ScreenToLatLong(List<PDBPoint> points) {
    List<PDBPoint> res = new ArrayList<PDBPoint>();
    for (PDBPoint point : points) {
      res.add(this.ScreenToLatLong(point));
    }
    return res;
  }
}

double snapTimestamp(double timestamp) {
  return (double)((int)(timestamp / MEASUREMENT_INTERVAL)) * MEASUREMENT_INTERVAL;
}

double getFirstWeekdayOfMonth(double timestamp, int weekday) {
  Calendar c = new GregorianCalendar();
  c.setTimeZone(TimeZone.getTimeZone("GMT"));
  c.setTimeInMillis((long)(timestamp * 1000.0));
  c.set(Calendar.DAY_OF_WEEK_IN_MONTH, 1);
  c.set(Calendar.DAY_OF_WEEK, weekday);
  c.set(GregorianCalendar.HOUR_OF_DAY, 0);
  c.set(GregorianCalendar.MINUTE, 0);
  c.set(GregorianCalendar.SECOND, 0);
  return (double)c.getTimeInMillis() / (double)1000.0;
}

DateTime TimestampToDateTime(double timestamp) {
  Calendar c = new GregorianCalendar();
  c.setTimeZone(TimeZone.getTimeZone("GMT"));
  c.setTimeInMillis((long)(timestamp * 1000.0));
  return new DateTime(c);
}

double MakeTimestamp(DateTime dt) {
  return (double)dt.c.getTimeInMillis() / (double)1000.0;
}

double MakeTimestamp(int month, int day, int year) {
  return MakeTimestamp(month, day, year, 0, 0, 0);
}

double MakeTimestamp(int month, int day, int year, int hour, int minute, int second) {
  Calendar c = new GregorianCalendar();
  c.setTimeZone(TimeZone.getTimeZone("GMT"));
  c.set(GregorianCalendar.MONTH, month - 1);
  c.set(GregorianCalendar.DAY_OF_MONTH, day);
  c.set(GregorianCalendar.YEAR, year);
  c.set(GregorianCalendar.HOUR_OF_DAY, hour);
  c.set(GregorianCalendar.MINUTE, minute);
  c.set(GregorianCalendar.SECOND, second);
  return (double)c.getTimeInMillis() / (double)1000.0;
}

double offsetDays(int days) {
  return days * 86400.0; // seconds in a day
}

double offsetWeeks(int weeks) {
  return weeks * 604800.0; // seconds in a week
}


double offsetTime(int hours, int minutes, int seconds) {
  return seconds + 60.0 * (minutes + 60.0 * hours);
}


class DateTime {

  Calendar c;

  DateTime(Calendar _c) {
    this.c = _c;
    this.c.setTimeZone(TimeZone.getTimeZone("GMT"));
  }

  DateTime(double timestamp) {
    this.c = new GregorianCalendar();
    this.c.setTimeZone(TimeZone.getTimeZone("GMT"));
    this.c.setTimeInMillis((long)(timestamp * 1000.0));
  }

  int getYear() {
    return c.get(GregorianCalendar.YEAR);
  }

  int getMonth() {
    return c.get(GregorianCalendar.MONTH) + 1;
  }

  String getMonthName() {
    String[] months = {
      "January", "February", "March", "April", 
      "May", "June", "July", "August", "September", 
      "October", "November", "December"
    };
    return months[this.getMonth() - 1];
  }

  String getMonthAbbreviation() {
    return this.getMonthName().substring(0, 3).toUpperCase();
  }

  int getTotalDaysInMonth() {
    return c.getActualMaximum(Calendar.DAY_OF_MONTH);
  }

  int getWeekOfYear() {
    return c.get(GregorianCalendar.WEEK_OF_YEAR);
  }

  int getWeekofMonth() {
    return c.get(GregorianCalendar.WEEK_OF_MONTH);
  }

  int getDayOfYear() {
    return c.get(GregorianCalendar.DAY_OF_YEAR);
  }

  int getDayOfMonth() {
    return c.get(GregorianCalendar.DAY_OF_MONTH);
  }

  int getDay() {
    return this.getDayOfMonth();
  }


  String getDayOfWeekName() {
    int day = this.getDayOfWeek();
    if (day == Calendar.MONDAY) return "Monday";
    if (day == Calendar.TUESDAY) return "Tuesday";
    if (day == Calendar.WEDNESDAY) return "Wednesday";
    if (day == Calendar.THURSDAY) return "Thursday";
    if (day == Calendar.FRIDAY) return "Friday";
    if (day == Calendar.SATURDAY) return "Saturday";
    if (day == Calendar.SUNDAY) return "Sunday";
    return "";
  }

  String getDayOfWeekAbbreviation() {
    return this.getDayOfWeekName().substring(0, 3).toUpperCase();
  }

  int getDayOfWeek() {
    return c.get(GregorianCalendar.DAY_OF_WEEK);
  }

  int getHour() {
    return c.get(GregorianCalendar.HOUR_OF_DAY);
  }

  int getMinute() {
    return c.get(GregorianCalendar.MINUTE);
  }

  int getSecond() {
    return c.get(GregorianCalendar.SECOND);
  }

  String toString() {
    return this.stringFull();
  }

  String stringMDY() {
    return String.format("%02d/%02d/%04d", getMonth(), getDay(), getYear());
  }

  String stringHMS() {
    return String.format("%02d:%02d:%02d", getHour(), getMinute(), getSecond());
  }

  String stringFull() {
    return String.format("%s %s/%02d/%04d @ %02d:%02d:%02d", getDayOfWeekAbbreviation(), getMonthName(), getDay(), getYear(), getHour(), getMinute(), getSecond());
  }
}

void annulus(float x, float y, float start, float end, float inner, float outer) {
  strokeWeight(1);
  stroke(255,125);
  //noStroke();
  
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
}

