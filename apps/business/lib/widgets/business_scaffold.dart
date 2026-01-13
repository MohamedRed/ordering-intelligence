import 'package:flutter/material.dart';

import 'business_drawer.dart';

/// Responsive scaffold for the business app:
/// - On narrow screens: uses the hamburger Drawer.
/// - On wide screens: shows a persistent left navigation sidebar.
class BusinessScaffold extends StatefulWidget {
  const BusinessScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.drawerBreakpoint = 1100,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// Minimum width to switch from Drawer to persistent sidebar.
  final double drawerBreakpoint;

  @override
  State<BusinessScaffold> createState() => _BusinessScaffoldState();
}

class _BusinessScaffoldState extends State<BusinessScaffold> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= widget.drawerBreakpoint;

        if (!wide) {
          return Scaffold(
            appBar: AppBar(
              title: widget.title,
              actions: widget.actions,
              centerTitle: true,
            ),
            drawer: const BusinessDrawer(),
            body: widget.body,
            floatingActionButton: widget.floatingActionButton,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: _collapsed ? 84 : 300,
                    child: BusinessNavigationSidebar(
                      includeTopSafeArea: false,
                      collapsed: _collapsed,
                    ),
                  ),
                  _CollapseHandle(
                    isCollapsed: _collapsed,
                    onTap: () => setState(() => _collapsed = !_collapsed),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: kToolbarHeight,
                      child: AppBar(
                        automaticallyImplyLeading: false,
                        title: widget.title,
                        actions: widget.actions,
                        centerTitle: true,
                      ),
                    ),
                    Expanded(child: widget.body),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: widget.floatingActionButton,
        );
      },
    );
  }
}

class _CollapseHandle extends StatelessWidget {
  const _CollapseHandle({
    required this.isCollapsed,
    required this.onTap,
  });

  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: 12,
      right: -10,
      child: Material(
        color: cs.surface,
        shape: const StadiumBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            child: Icon(
              isCollapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
