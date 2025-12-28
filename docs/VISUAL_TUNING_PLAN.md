# Visual Tuning Plan: Matching Interstellar's Gargantua

## Research Summary

Based on analysis of Double Negative's work with Kip Thorne:

- DNEG created a custom renderer (DNGR) that traced light beams through curved spacetime
- They used the Tycho-2 catalogue (2.5M stars) for the background
- Relativistic aberration, Doppler shifts, and gravitational redshifts were all computed
- **Key artistic choice**: The extreme red/blue Doppler shifts were "toned down severely" for dramatic appeal
- The final look is "brighter and more symmetric" than pure physics would dictate

---

## Phase 1: Accretion Disk Refinement

### 1.1 Disk Geometry
**Current**: Inner=3.0, Outer=14.0, Height=0.05
**Target**: Match Interstellar's very thin, crisp appearance

Tasks:
- [ ] Reduce disk height further (0.02-0.03)
- [ ] Sharpen inner edge cutoff (ISCO boundary)
- [ ] Add subtle disk warping near inner edge
- [ ] Reduce outer edge fade distance for crisper boundary

### 1.2 Disk Texture
**Current**: FBM noise with spiral arms
**Target**: Smoother, more coherent structure with subtle detail

Tasks:
- [ ] Reduce turbulence intensity (less noisy)
- [ ] Make spiral arms more subtle
- [ ] Add concentric ring structure (orbit bands)
- [ ] Increase contrast between dense/sparse regions

### 1.3 Temperature Profile
**Current**: Simple r^-0.75 profile
**Target**: More dramatic inner edge glow, realistic falloff

Tasks:
- [ ] Enhance inner edge brightness (ISCO glow)
- [ ] Adjust temperature scaling for warmer colors
- [ ] Add localized hotspots that orbit realistically

---

## Phase 2: Color Palette (Critical!)

### 2.1 Blackbody Color Function
**Current**: Red → Orange → Yellow → White progression
**Target**: Interstellar's distinctive warm gold/orange palette

The movie uses a specific color palette that's warmer and more golden than pure blackbody radiation.

Tasks:
- [ ] Shift color curve toward orange/gold (less red, less white)
- [ ] Reduce blue contribution entirely
- [ ] Add subtle color variation based on disk structure
- [ ] Inner disk: bright gold/white
- [ ] Mid disk: warm orange
- [ ] Outer disk: deep orange/amber

### 2.2 Doppler Color Shift
**Current**: Full relativistic Doppler (can be extreme)
**Target**: Subtle, toned-down Doppler for cinematic look

Tasks:
- [ ] Reduce Doppler intensity multiplier (g^3 → g^2 or g^1.5)
- [ ] Clamp color shift range tighter
- [ ] Approaching side: slightly brighter, subtly bluer
- [ ] Receding side: slightly dimmer, subtly redder
- [ ] Overall: keep both sides recognizably orange

### 2.3 Gravitational Redshift
**Current**: sqrt(1 - rs/r) correction
**Target**: Subtle dimming toward inner edge

Tasks:
- [ ] Reduce redshift visual impact
- [ ] Maintain brightness of inner disk

---

## Phase 3: Einstein Ring & Lensing

### 3.1 Secondary Disk Images
**Current**: Detected via disk crossings
**Target**: Clear, distinct secondary image visible above/below

Tasks:
- [ ] Increase brightness boost for secondary crossings
- [ ] Ensure secondary image is clearly visible
- [ ] Add subtle tertiary image contribution
- [ ] Match the "disk wrapping around" look

### 3.2 Photon Ring
**Current**: Gaussian glow at r=3M
**Target**: Sharp, bright thin ring at shadow edge

Tasks:
- [ ] Make photon ring thinner and brighter
- [ ] Add multiple sub-rings (exponentially stacked)
- [ ] Color should match disk (warm orange/gold)
- [ ] Ring should be most visible at disk plane intersection

### 3.3 Star Field Lensing
**Current**: Basic lensing amplification
**Target**: Visible distortion of background stars

Tasks:
- [ ] Increase star density for more visible lensing
- [ ] Enhance lensing distortion near photon sphere
- [ ] Add star streaking effect for highly deflected rays
- [ ] Consider adding distant galaxy/nebula for dramatic lensing

---

## Phase 4: Black Hole Shadow

### 4.1 Shadow Shape
**Current**: Circular absorption at r < RS*0.52
**Target**: Crisp, perfectly dark shadow

Tasks:
- [ ] Ensure shadow is completely black (no leakage)
- [ ] Sharpen shadow edge
- [ ] Verify shadow size matches photon sphere correctly

### 4.2 Shadow Edge
**Current**: Subtle edge glow
**Target**: Clean edge with photon ring just outside

Tasks:
- [ ] Remove or minimize edge glow inside shadow
- [ ] Ensure photon ring sits just outside shadow
- [ ] Add subtle "limb darkening" effect approaching shadow

---

## Phase 5: Post-Processing (Cinematic Look)

### 5.1 Bloom
**Current**: Simple threshold bloom
**Target**: Cinematic glow around bright regions

Tasks:
- [ ] Multi-pass bloom (different radii)
- [ ] Bloom should spread warmly from disk
- [ ] Avoid blooming into shadow region

### 5.2 Tone Mapping
**Current**: ACES
**Target**: Filmic, high dynamic range feel

Tasks:
- [ ] Adjust ACES parameters for warmer output
- [ ] Increase contrast slightly
- [ ] Ensure deep blacks are preserved

### 5.3 Color Grading
**Current**: Slight warm tint (r*1.03, b*0.94)
**Target**: Interstellar's distinctive color grade

Tasks:
- [ ] Push further toward warm/amber
- [ ] Reduce blue channel more aggressively
- [ ] Add subtle highlight desaturation
- [ ] Shadow color: neutral to warm black

### 5.4 Film Effects
**Current**: Basic grain and vignette
**Target**: IMAX/70mm film aesthetic

Tasks:
- [ ] Adjust grain size and intensity
- [ ] Vignette: subtle, centered on black hole
- [ ] Consider subtle chromatic aberration at edges
- [ ] Optional: 2.39:1 letterboxing for cinematic aspect

---

## Phase 6: Performance Optimization

After visual tuning, optimize for smooth playback:

Tasks:
- [ ] Profile shader performance
- [ ] Reduce MAX_STEPS if possible without quality loss
- [ ] Optimize noise functions
- [ ] Add quality preset toggle (Low/Medium/High)

---

## Implementation Order

1. **Color palette first** (biggest visual impact)
2. **Disk geometry** (sharper, thinner)
3. **Einstein ring clarity** (secondary images)
4. **Post-processing** (cinematic feel)
5. **Fine-tuning** (photon ring, stars, shadow)
6. **Performance** (optimization)

---

## Reference Values

### Interstellar's Gargantua Parameters
- Spin: a/M ≈ 0.998 (near-extremal) ✓
- Mass: ~100 million solar masses (cosmetic only)
- Inclination: ~10° above disk plane (edge-on view)
- Disk appears both above AND below the shadow

### Target Color Palette (approximate RGB)
- Hot inner disk: rgb(255, 220, 180) - bright warm white
- Mid disk: rgb(255, 170, 80) - golden orange
- Outer disk: rgb(255, 130, 50) - deep orange
- Photon ring: rgb(255, 200, 140) - bright gold
- Shadow: rgb(0, 0, 0) - pure black

---

## Success Criteria

The visualization should evoke the feeling of Interstellar's Gargantua:
- [ ] Warm, golden-orange color palette (not red, not white)
- [ ] Thin, crisp accretion disk
- [ ] Visible secondary image (disk "wrapping around")
- [ ] Bright photon ring at shadow edge
- [ ] Asymmetric brightness (Doppler) but not extreme
- [ ] Clean, dark circular shadow
- [ ] Cinematic, film-like quality
- [ ] Smooth real-time performance (30+ FPS)
