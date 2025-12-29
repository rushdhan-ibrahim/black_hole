# Volumetric Accretion Disk Enhancement Plan

## Goal
Transform the accretion disk from a 2D plane-crossing model to a true 3D volumetric structure with visible thickness, vertical filament motion, and realistic turbulent "puffiness" while maintaining 31+ FPS.

---

## Current State Analysis

### Current Implementation (`fragment.glsl`)
- **Disk Detection**: Binary plane-crossing at y=0
  ```glsl
  bool crossedDisk = (lastY * newPos.y < 0.0);
  ```
- **Disk Height**: `DISK_HEIGHT 0.015` (essentially 2D)
- **Sampling**: Only at exact crossing point
- **Result**: Disk appears flat, volume only perceived through gravitational lensing

### Reference Implementation (`gargantua_v0_cev.html`)
- **Disk Detection**: Volumetric sampling every ray march step
- **Vertical Profile**: Gaussian density distribution
  ```glsl
  float x = d / max(thick, 1e-6);
  float verticalW = exp(-0.5 * x*x);  // Gaussian
  ```
- **Disk Height**: Scale height H with radial flaring
  ```glsl
  float H0 = 0.045 - 0.070;  // Base half-height
  float flare = 0.90 + 0.35 * (r/r_inner - 1.0) / 6.0;
  float H = H0 * flare;
  ```
- **FBM Warp**: Adds 3D turbulent displacement
- **Result**: Disk has visible thickness and 3D structure

---

## Physics Background

### Real Accretion Disk Structure

1. **Vertical Extent**
   - Disks have finite thickness: H/r ~ 0.01-0.1 (thin disk limit)
   - Supported by thermal/radiation pressure and turbulent motions
   - Scale height increases with radius (flaring)

2. **Density Profile**
   - Vertical: Approximately Gaussian (hydrostatic equilibrium)
   - ρ(z) ~ exp(-z²/2H²)
   - Peak density at midplane, falls off exponentially

3. **Vertical Motion**
   - MHD turbulence drives vertical oscillations
   - Magnetic field loops create vertical filament structures
   - Timescale: ~orbital period / few

4. **Appearance**
   - Edge-on: Visible thickness with bright midplane
   - Face-on: Subtle vertical motion creates "breathing" texture
   - Lensing: Top/bottom surfaces both visible near black hole

---

## Implementation Plan

### Phase 1: Volumetric Integration Framework
**Goal**: Replace plane-crossing with continuous volumetric sampling

**Changes Required**:

1. **Remove Plane-Crossing Detection**
   ```glsl
   // REMOVE this binary approach:
   // bool crossedDisk = (lastY * newPos.y < 0.0);
   ```

2. **Add Volumetric Sampling Every Step**
   ```glsl
   // Sample disk contribution at every step
   float diskY = abs(pos.y);  // Distance from midplane
   float diskR = length(pos.xz);

   // Only sample within vertical extent
   if (diskR > DISK_INNER * 0.92 && diskR < DISK_OUTER * 1.08) {
       float H = getDiskScaleHeight(diskR);
       if (diskY < H * 4.0) {  // Within 4 scale heights
           vec4 diskData = sampleDiskVolumetric(pos, vel, uTime, H);
           // Accumulate with volumetric integration
       }
   }
   ```

3. **Volumetric Accumulation**
   ```glsl
   // Proper volumetric integration
   float dTau = diskData.a * stepLength;
   float alpha = 1.0 - exp(-dTau);
   col += diskData.rgb * alpha * transmission;
   transmission *= (1.0 - alpha);
   ```

**Performance Impact**: ~2-3 FPS (more samples per ray)

---

### Phase 2: Gaussian Vertical Density Profile
**Goal**: Physically realistic vertical falloff

**Implementation**:
```glsl
float getDiskScaleHeight(float r) {
    // Base scale height (thin disk: H/r ~ 0.03-0.05)
    float H0 = 0.05;

    // Radial flaring (disk gets thicker at larger radii)
    float rNorm = (r - DISK_INNER) / (DISK_OUTER - DISK_INNER);
    float flare = 1.0 + 0.4 * rNorm;  // 1.0 at inner, 1.4 at outer

    return H0 * r * flare;
}

float verticalDensity(float y, float H) {
    float x = abs(y) / max(H, 0.001);
    return exp(-0.5 * x * x);  // Gaussian profile
}
```

**Parameters to Tune**:
- `H0`: Base aspect ratio (0.03-0.08)
- `flare`: How much disk thickens with radius (1.2-1.6x)
- `cutoff`: How many scale heights to render (3-5)

**Performance Impact**: Minimal (~0.5 FPS)

---

### Phase 3: Y-Axis Filament Oscillations
**Goal**: Vertical filament motion creating 3D texture feel

**Approach**: Add vertical displacement to filament system

```glsl
// Vertical oscillation for each filament band
float verticalOscillation(float phi, float r, float time, float freq) {
    float omega = sqrt(M / (r * r * r));

    // Vertical mode oscillation (breathing)
    float vOsc1 = sin(phi * freq * 0.3 + time * omega * 2.0) * 0.02;

    // Magnetic loop-like structures
    float vOsc2 = sin(phi * freq * 0.8 - r * 3.0 + time * 1.5) * 0.015;

    // Turbulent vertical displacement
    float vTurb = (noise(vec3(phi * 5.0, r * 2.0, time * 0.8)) - 0.5) * 0.025;

    return vOsc1 + vOsc2 + vTurb;
}
```

**Per-Filament Band Vertical Offset**:
```glsl
// In sampleDiskVolumetric:
float yOffset1 = verticalOscillation(rotPhi, r, time, 40.0);
float yOffset2 = verticalOscillation(rotPhi, r, time, 85.0);
float yOffset3 = verticalOscillation(rotPhi, r, time, 160.0);

// Modify filament contribution based on actual y position
float band1Contrib = band1 * verticalDensity(posY - yOffset1 * r, H);
float band2Contrib = band2 * verticalDensity(posY - yOffset2 * r, H);
float band3Contrib = band3 * verticalDensity(posY - yOffset3 * r, H);
```

**Effect**: Filaments appear to undulate vertically, creating 3D motion

**Performance Impact**: ~1-2 FPS

---

### Phase 4: FBM Vertical Warping
**Goal**: Large-scale 3D turbulent structure

**Implementation**:
```glsl
float getVerticalWarp(float phi, float r, float time) {
    float u = log(r / DISK_INNER + 0.1);
    float v = phi + time * 0.05;  // Slow azimuthal drift

    // Multi-scale FBM warp
    float warp = 0.0;
    warp += noise(vec3(u * 1.5, v * 0.4, time * 0.1)) * 0.5;
    warp += noise(vec3(u * 3.0, v * 0.8, time * 0.15)) * 0.25;
    warp -= 0.375;  // Center around 0

    return warp * 0.06;  // Scale to disk height units
}
```

**Application**:
```glsl
// Warp the effective y-coordinate for sampling
float warpedY = posY + getVerticalWarp(phi, r, time) * r;
float vertW = verticalDensity(warpedY, H);
```

**Effect**: Disk surface appears to have large-scale "waves" and "bulges"

**Performance Impact**: ~1 FPS (reuse existing noise)

---

### Phase 5: Optimized Volumetric Sampling
**Goal**: Maximize visual quality within FPS budget

**Optimization Strategies**:

1. **Adaptive Sampling Near Disk**
   ```glsl
   // Reduce step size when inside disk volume
   float diskProximity = 1.0 - min(diskY / (H * 4.0), 1.0);
   if (diskProximity > 0.0 && diskR > DISK_INNER * 0.9) {
       h *= 0.6;  // Finer steps in disk
   }
   ```

2. **Early Opacity Termination**
   ```glsl
   // Stop sampling when disk is opaque
   if (transmission < 0.02) break;
   ```

3. **LOD Filament System**
   ```glsl
   // Reduce filament layers when far from camera
   float distFactor = smoothstep(20.0, 50.0, length(pos - ro));
   int numBands = int(mix(4.0, 2.0, distFactor));
   ```

4. **Precomputed Values**
   ```glsl
   // Compute once per sample point
   float omega = sqrt(M / (r * r * r));
   float rotPhi = phi + time * omega * 0.35;
   float logR = log(r / DISK_INNER + 0.1);
   // Reuse for all filament/spiral calculations
   ```

**Performance Budget**:
| Component | Before | After |
|-----------|--------|-------|
| Ray marching | 15 FPS | 15 FPS |
| Volumetric sampling | 8 FPS | 11 FPS |
| Filaments + turbulence | 8 FPS | 10 FPS |
| Vertical effects | 0 FPS | 2 FPS |
| Post-processing | 2 FPS | 2 FPS |
| **Headroom** | **14 FPS** | **9 FPS** |

Target: 31+ FPS (9 FPS headroom for safety)

---

### Phase 6: Einstein Ring Preservation
**Goal**: Maintain multi-crossing Einstein ring effect with volumetric model

**Challenge**: Volumetric model accumulates continuously, may wash out distinct ring layers

**Solution**: Track crossing events within volumetric integration
```glsl
// Count significant plane crossings for brightness boost
if (lastY * pos.y < 0.0) {
    diskCrossings++;
}

// Apply Einstein ring boost based on crossing count
float einsteinBoost = 1.0;
if (diskCrossings == 2) einsteinBoost = 2.0;
if (diskCrossings > 2) einsteinBoost = 2.5 + float(diskCrossings - 2) * 0.3;

// Apply to volumetric sample
diskData.a *= einsteinBoost;
```

---

## Implementation Order

### Step 1: Basic Volumetric Framework
- Replace plane-crossing with volumetric sampling loop
- Implement basic vertical density (Gaussian)
- Verify Einstein ring still visible
- **Target**: 28+ FPS

### Step 2: Scale Height & Flaring
- Add proper scale height function
- Implement radial flaring
- Tune H0 and flare parameters
- **Target**: 28+ FPS

### Step 3: Vertical Filament Motion
- Add per-band vertical oscillation
- Implement magnetic loop structures
- Test vertical animation
- **Target**: 27+ FPS

### Step 4: FBM Warping
- Add large-scale vertical warp
- Tune warp amplitude and frequency
- Verify no visual artifacts
- **Target**: 26+ FPS

### Step 5: Optimization Pass
- Implement adaptive sampling
- Add LOD for distant views
- Profile and optimize hotspots
- **Target**: 31+ FPS

### Step 6: Final Tuning
- Balance visual quality vs performance
- Adjust all parameters for best look
- Test at various zoom levels and angles
- **Target**: 31+ FPS stable

---

## Testing Checklist

### Visual Quality
- [ ] Disk has visible thickness from edge-on view
- [ ] Vertical density falloff looks natural (no sharp edges)
- [ ] Filaments appear to move in 3D (not just radially)
- [ ] Large-scale turbulent "puffiness" visible
- [ ] Einstein ring effect preserved
- [ ] Face-on view shows subtle vertical texture
- [ ] Gravitational lensing shows top/bottom disk surfaces

### Performance
- [ ] Default view (distance 35): 31+ FPS
- [ ] Zoomed in (distance 20): 28+ FPS
- [ ] Zoomed out (distance 80): 35+ FPS
- [ ] Edge-on view: 28+ FPS
- [ ] Smooth rotation at all angles
- [ ] No stuttering during continuous motion

### Edge Cases
- [ ] Very close zoom doesn't break rendering
- [ ] Pole view (looking straight down) renders correctly
- [ ] Equatorial view shows proper disk profile
- [ ] No aliasing or banding artifacts
- [ ] Color/brightness consistent with previous look

---

## Fallback Options (if FPS drops below 28)

1. **Reduce Scale Height**
   - Smaller H0 = fewer steps inside disk
   - Trade: Less visible thickness

2. **Fewer Filament Bands**
   - Remove highest frequency bands (400-450)
   - Trade: Less fine detail

3. **Simpler Vertical Motion**
   - Single oscillation instead of per-band
   - Trade: Less complex 3D motion

4. **Lower FBM Octaves**
   - Single noise call instead of multi-scale
   - Trade: Less turbulent structure

5. **Conditional Volumetric**
   - Only volumetric near equator (|elevation| < 30°)
   - Plane-crossing for edge-on views
   - Trade: Inconsistent at some angles

6. **Resolution Reduction**
   - Drop to 0.9 DPR
   - Trade: Overall image quality

---

## Constants & Parameters Summary

```glsl
// Volumetric disk parameters
#define DISK_H0 0.05           // Base scale height ratio
#define DISK_FLARE 0.4         // Flaring coefficient
#define DISK_CUTOFF 4.0        // Sample within N scale heights

// Vertical motion
#define VERT_OSC_AMP 0.02      // Oscillation amplitude
#define VERT_TURB_AMP 0.025    // Turbulent displacement
#define VERT_WARP_AMP 0.06     // FBM warp amplitude

// Sampling
#define DISK_STEP_FACTOR 0.6   // Step size reduction in disk
#define OPACITY_CUTOFF 0.02    // Early termination threshold
```

---

## Notes

- The reference implementation uses Boyer-Lindquist coordinates and Kerr geodesics; our implementation uses simplified Schwarzschild with pseudo-force approximation. Volumetric approach should adapt similarly.

- Key visual difference: Interstellar's disk has "wisps" that extend above/below the plane - this is what we're trying to achieve with vertical filament motion and FBM warping.

- The disk should look like it has "atmosphere" - not a hard surface, but a gradual density falloff that the light passes through and illuminates.
