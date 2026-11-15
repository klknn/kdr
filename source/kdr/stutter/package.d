/**
 * Root package for kdr-stutter (Stutter Edit 2 clone).
 * Exposes core parameters, client, buffer engines, TVM sequencer, and FX suite.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter;

// Core parameter declarations
public import kdr.stutter.params;

// Core stutter, buffer, and gesture engines
public import kdr.stutter.buffer;
public import kdr.stutter.stutter;
public import kdr.stutter.gesture;

// TVM Curve Sequencer & Modulation
public import kdr.stutter.tvm;

// 11 FX Modules + End-of-Chain Delay + Master Limiter
public import kdr.stutter.fx;

// Factory Presets & Gesture Banks
public import kdr.stutter.presets;

// Client lifecycle & GUI
public import kdr.stutter.client;
public import kdr.stutter.gui;
