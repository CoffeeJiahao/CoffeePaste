# Tab 翻页问题修复 - Product Requirement Document

## Overview
- **Summary**: 修复 CoffeePaste 应用中 tab 键翻页功能仅第一次有效的问题
- **Purpose**: 确保用户可以连续使用 tab（或 shift+tab）键来向前/向后翻页浏览剪贴板历史记录
- **Target Users**: 所有使用 CoffeePaste 的用户

## Goals
- 修复 tab 键翻页功能，让它可以连续响应多次按下
- 保持所有其他功能正常工作
- 符合 Swift 6 并发安全要求

## Non-Goals (Out of Scope)
- 不修改任何其他 UI 或功能
- 不重构现有代码架构

## Background & Context
通过代码分析，我找到了问题的根源：

1. 当面板显示时，AppDelegate.showPanel() 方法自动将搜索框设置为第一响应者（PanelView.swift 427-433 行也会再次聚焦搜索框）
2. 当搜索框（TextField）具有焦点时，Tab 键被 TextField 捕获用于焦点导航，而不是被 CustomPanel.sendEvent(_:) 方法捕获
3. 因此，只有第一次按下 Tab 时可能有反应，之后 Tab 键就被 TextField 完全接管了

## Functional Requirements
- **FR-1**: 用户能够使用 Tab 键向前翻页
- **FR-2**: 用户能够使用 Shift+Tab 键向后翻页
- **FR-3**: 翻页功能能够连续响应，不限于仅一次
- **FR-4**: 搜索功能仍然正常工作

## Non-Functional Requirements
- **NFR-1**: 代码符合 Swift 6 严格并发要求
- **NFR-2**: 保持动画流畅
- **NFR-3**: 修复方案简洁，不引入复杂性

## Constraints
- **Technical**: macOS 15+, Swift 6, SwiftUI + AppKit
- **Dependencies**: 无新增依赖

## Assumptions
- 用户希望保留搜索功能
- 用户希望保留 Tab 键翻页功能

## Acceptance Criteria

### AC-1: Tab 键能连续向前翻页
- **Given**: 面板已打开且有多个页面的剪贴板历史
- **When**: 用户连续多次按下 Tab 键
- **Then**: 每次按下都能正常向前翻一页
- **Verification**: human-judgment

### AC-2: Shift+Tab 键能连续向后翻页
- **Given**: 面板已打开且在非第一页
- **When**: 用户连续多次按下 Shift+Tab 键
- **Then**: 每次按下都能正常向后翻一页
- **Verification**: human-judgment

### AC-3: 搜索功能正常工作
- **Given**: 面板已打开
- **When**: 用户在搜索框输入文字
- **Then**: 搜索功能正常过滤剪贴板记录
- **Verification**: human-judgment

### AC-4: 焦点管理合理
- **Given**: 面板已打开
- **When**: 用户点击搜索框
- **Then**: 搜索框能正常获得焦点并允许输入
- **Verification**: human-judgment

## Open Questions
- 无
