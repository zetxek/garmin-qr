using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Timer;

class App extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new AppView() ];
    }
}

class AppView extends WatchUi.View {
    var images;
    var currentImageIndex;
    var imageY;
    var animationTimer;
    var isAnimating;
    var animationProgress;
    var nextImageIndex;
    var animationDirection;

    function initialize() {
        View.initialize();
        images = [
            Application.loadResource(Rez.Drawables.DisplayImage1),
            Application.loadResource(Rez.Drawables.DisplayImage2)
        ];
        currentImageIndex = 0;
        imageY = 0;
        isAnimating = false;
        animationProgress = 0;
        animationTimer = new Timer.Timer();
    }

    function onLayout(dc) {
    }

    function onShow() {
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        
        // Clear the screen
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        
        if (isAnimating && currentImageIndex >= 0 && currentImageIndex < images.size() && 
            nextImageIndex >= 0 && nextImageIndex < images.size()) {
            try {
                // Draw both images during animation
                var currentImage = images[currentImageIndex];
                var nextImage = images[nextImageIndex];
                
                // Center images horizontally and vertically
                var currentX = (screenWidth - currentImage.getWidth()) / 2;
                var currentY = (screenHeight - currentImage.getHeight()) / 2;
                var nextX = (screenWidth - nextImage.getWidth()) / 2;
                var nextY = (screenHeight - nextImage.getHeight()) / 2;
                
                // Add animation offset
                currentY += animationDirection * screenHeight * animationProgress;
                nextY += animationDirection * screenHeight * (animationProgress - 1);
                
                dc.drawBitmap(currentX, currentY, currentImage);
                dc.drawBitmap(nextX, nextY, nextImage);
            } catch (e) {
                System.println("Error during animation: " + e.getErrorMessage());
                isAnimating = false;
                animationTimer.stop();
            }
        } else {
            // Draw only the current image when not animating
            if (currentImageIndex >= 0 && currentImageIndex < images.size()) {
                try {
                    var image = images[currentImageIndex];
                    var x = (screenWidth - image.getWidth()) / 2;
                    var y = (screenHeight - image.getHeight()) / 2;
                    dc.drawBitmap(x, y, image);
                } catch (e) {
                    System.println("Error drawing current image: " + e.getErrorMessage());
                }
            }
        }
    }

    function onHide() {
        if (animationTimer != null) {
            animationTimer.stop();
        }
    }

    function startAnimation(direction) {
        if (!isAnimating) {
            isAnimating = true;
            animationProgress = 0;
            animationDirection = direction;
            
            // Calculate next image index
            if (direction > 0) {
                // Swipe up - move to next image
                nextImageIndex = currentImageIndex + 1;
                if (nextImageIndex >= images.size()) {
                    nextImageIndex = 0;
                }
            } else {
                // Swipe down - move to previous image
                nextImageIndex = currentImageIndex - 1;
                if (nextImageIndex < 0) {
                    nextImageIndex = images.size() - 1;
                }
            }
            
            // Safety check
            if (nextImageIndex >= 0 && nextImageIndex < images.size()) {
                animationTimer.start(method(:onAnimationTimer), 16, true); // ~60fps
            } else {
                isAnimating = false;
                System.println("Invalid nextImageIndex: " + nextImageIndex);
            }
        }
    }

    function onAnimationTimer() {
        if (!isAnimating) {
            animationTimer.stop();
            return;
        }

        animationProgress += 0.1; // Adjust this value to change animation speed
        
        if (animationProgress >= 1.0) {
            animationTimer.stop();
            isAnimating = false;
            currentImageIndex = nextImageIndex;
            animationProgress = 0;
        }
        
        WatchUi.requestUpdate();
    }

    function onSwipe(swipeEvent) {
        if (!isAnimating) {
            if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
                startAnimation(1); // Upward animation
            } else if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
                startAnimation(-1); // Downward animation
            }
        }
        return true;
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_ENTER) {
            // Up button or Enter pressed - show next image
            startAnimation(1);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            // Down button pressed - show previous image
            startAnimation(-1);
            return true;
        }
        
        return false;
    }
} 