import java.util.Arrays;
import java.awt.Point;

final class Visualizer {

    private float historyDuration = 5f; // seconds
  
    private float maximumAmplitude = 0f;
    private float maximumFrequency = 20000; // Hz
    private float maximumLoudness = 0f;
    
    // Needed for analyzer history visualization.
    private TimedQueue loudnessHistory = new TimedQueue(historyDuration);
    private TimedQueue averageHistory = new TimedQueue(historyDuration);
    private TimedQueue thresholdHistory = new TimedQueue(historyDuration);
    
    private float triggerPaneY = int(0.06 * height);
    private boolean leftPaneIsOn = true;

    void update(FFT fft, boolean didDetectBeat) {
        background(0);
        showSpectrum(fft);
        showDetector();
        showTriggerPane(didDetectBeat);
    }

    private List<TimedQueue> allHistories() {
        return Arrays.asList(loudnessHistory, averageHistory, thresholdHistory);
    }

    private void showSpectrum(FFT fft) {
        int bandCount = int(maximumFrequency / fft.getBandWidth());
        int bandLengthX = Math.round(float(width) / float(bandCount));

        noStroke();
        fill(60);

        // Draws the band intensities.
        for (int band = 0; band <= bandCount; band++) {
            int xOffset = Math.round((width - bandLengthX) * band / (float) bandCount);

            float amplitude = fft.getBand(band);
            maximumAmplitude = max(maximumAmplitude, amplitude);

            int bandY = (int) map(amplitude, 0, maximumAmplitude, height, triggerPaneY);
            
            rect(xOffset, bandY, bandLengthX, height - bandY);
        }
    }

    private void showDetector() {
        maximumLoudness = max(maximumLoudness, detector.currentLoudness);
      
        loudnessHistory.add(detector.currentLoudness);
        averageHistory.add(detector.averageLoudness);
        thresholdHistory.add(detector.beatLoudness);
        
        List<List<Point>> historyLines = new ArrayList <List<Point>>();
        for (TimedQueue history : allHistories()) {
            historyLines.add(pointsForHistory(history));
        }

        color[] lineColors = {
            color(255, 255, 255),
            color(255, 165, 0, 150),
            color(0, 255, 0),
        };

        strokeWeight(3);
        for (int historyIndex = 0; historyIndex < allHistories().size(); historyIndex++) {
            List<Point> line = pointsForHistory(allHistories().get(historyIndex));
            
          if (line.size() < 2) { break; }

            stroke(lineColors[historyIndex]);

            // Needed to connect NaN-points (meaning [y = -1]-points).
            Point lastGoodPoint = line.get(0);

            for (int pointIndex = 1; pointIndex < line.size(); pointIndex++) {
                // Point 1 is older than point 2.
                Point point1 = line.get(pointIndex - 1);
                Point point2 = line.get(pointIndex);

                // Draws segments that have a y-value of -1 as straight line between the enclosing "normal" points in a red color.
                // Y-values of -1 are produced by the pointsForHistory method, when a value is NaN.
                // A normal case when this occurs is when the trigger threshold is set to NaN as a result of bpm-limitation.

                if (point1.y != -1 && point2.y == -1) /*Transition from normal to NaN values.*/ {
                    lastGoodPoint = point1;
                } else if (point1.y == -1 && point2.y == -1) /*Mid NaN values.*/ {
                    // Draws a horizontal line if the mid-NaN passage is at the very end of the history (the newset thing happening).
                    if (point2.x == 0) {
                        stroke(200, 20, 30, 150);
                        line(lastGoodPoint.x, lastGoodPoint.y, point2.x, lastGoodPoint.y);
                        stroke(lineColors[historyIndex]);
                    }
                } else if (point1.y == -1 && point2.y != -1) /*Transition from NaN to normal values.*/ {
                    // Doesn't draw the transition if it's from a NaN-segement that's at the very beginning of the history (oldest thing), because then the lastGoodPoint is no help.
                    // This state can be detected by checking if the lastGoodPoint has changed to something other that line-get(0) yet.
                    // If not, we have not had a proper transition from normal values to NaN-values -> we are starting with a NaN-segment.
                    if (lastGoodPoint != line.get(0)) {
                        stroke(200, 20, 30, 150);
                        line(lastGoodPoint.x, lastGoodPoint.y, point2.x, point2.y);
                        stroke(lineColors[historyIndex]);
                    }
                } else /*Mid normal values.*/ {
                    line(point1.x, point1.y, point2.x, point2.y);
                }
            }
        }
    }

    private void showTriggerPane(boolean didTrigger) {      
        if (didTrigger) { 
            noStroke();
            fill(255, 100, 100, 150);
            rect(0, 0, width, triggerPaneY);
        }
        
        // Draws a seperator to the rest of the visualizations.
        stroke(255);
        strokeWeight(3);
        line(0, triggerPaneY, width, triggerPaneY);
    }

    // If any value is NaN the corresponding y-point will be -1.
    private List<Point> pointsForHistory(TimedQueue history) {
        List <Float> values = history.getValues();
        List <Integer> timeStamps = history.getTimeStamps();

        if (values.isEmpty()) {
            return new ArrayList<Point>();
        }

        int historyDurationMillis = int(historyDuration * 1000);
        int timeStampOffset = timeStamps.get(timeStamps.size() - 1) - historyDurationMillis;

        List<Point> points = new ArrayList<Point>();

        for (int index = 0; index < timeStamps.size(); index++) {
            int y = values.get(index).isNaN() ? -1 : ((int) map(values.get(index), 0, maximumLoudness, height, triggerPaneY));
            int x = Math.round(map(timeStamps.get(index) - timeStampOffset, 0, historyDurationMillis, width, 0));

            points.add(new Point(x, y));
        }

        return points;
    }
}
