import java.util.List;

final class TimedQueue {

    TimedQueue(float retentionDuration) {
      this.retentionDuration = retentionDuration;
    }

    private List<Float> values = new ArrayList<Float>();
    private List<Integer> timeStamps = new ArrayList<Integer>();
    private float retentionDuration; // in seconds

    private int startOfRelevantHistory() {
        if (timeStamps.isEmpty()) { return -1; }
    
        int now = millis();

        // Gets the index of the oldest time stamp not older than the retention duration. If there is none, -1 is returned.
        int index = 0;
        while (now - timeStamps.get(index) > retentionDuration * 1000) {
            index++;
            if (index == timeStamps.size()) { return -1; }
        }
    
        return index;
    }
  
    List<Float> getValues() {
        int startIndex = startOfRelevantHistory();
        if (startIndex < 0) { return new ArrayList<Float>(); }
    
        return values.subList(startIndex, values.size() - 1);
    }
    
    List<Integer> getTimeStamps() {
        int startIndex = startOfRelevantHistory();
        if (startIndex < 0) { return new ArrayList<Integer>(); }
    
        return timeStamps.subList(startIndex, timeStamps.size() - 1);
    }

    void add(float value) {
        int now = millis();
 
        values.add(value);
        timeStamps.add(now);

        // Removes the values that are older than the retention duration.
        // Removal only happens once at least 500 values have accumulated. This is done to reduce the runtime cost of reallocating array memory. 
        if (timeStamps.size() > 500) {
            // Removes the values only if the oldest recorded value is at least (2 * retention duration) old.
            // The factor 1000 converts the rentation duration from seconds to milliseconds. 
            if (now - timeStamps.get(0) > (2 * retentionDuration * 1000)) {
                int startIndex = startOfRelevantHistory();
    
                if (startIndex < 0) {
                    values = new ArrayList();
                    timeStamps = new ArrayList();
                } else {
                    values = values.subList(startIndex, values.size() - 1);
                    timeStamps = timeStamps.subList(startIndex, timeStamps.size() - 1);
                }
            }
        }
    }
}
