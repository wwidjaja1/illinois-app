import 'package:flutter/material.dart';
import 'package:illinois/ui/widgets/HeaderBar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:illinois/service/Gateway.dart';
import 'package:rokwire_plugin/service/styles.dart';
import 'package:rokwire_plugin/service/localization.dart';

import '../../model/StudentCourse.dart';

class DisplayFloorPlanPanel extends StatefulWidget {
  final Building? building;
  const DisplayFloorPlanPanel({super.key, this.building});

  @override
  State<DisplayFloorPlanPanel> createState() => _DisplayFloorPlanPanelState();
}

class _DisplayFloorPlanPanelState extends State<DisplayFloorPlanPanel> {
  late final WebViewController _controller;
  String _htmlWithFloorPlan = '';
  String _currentFloorCode = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
    //Enable Javascript for this WebView
    ..setJavaScriptMode(JavaScriptMode.unrestricted) // Enable JavaScript
    ..setBackgroundColor(Colors.transparent) // Optional: Transparent background
    ..setNavigationDelegate(
    NavigationDelegate(
    onPageStarted: (_) {
    setState(() {
    _isLoading = true; // Show loading indicator
    });
    },
    onPageFinished: (_) {
    setState(() {
    _isLoading = false; // Hide loading indicator
    });
    },
    ),
    );


    // Initialize only if building is provided
    if (widget.building != null) {
      List<String>? floors = widget.building?.floors;
      if (floors != null && floors.isNotEmpty) {
        _currentFloorCode = floors.first; // Set to the first floor code
        loadFloorPlan(_currentFloorCode);
      }
      else {
        _htmlWithFloorPlan = '${Localization().getStringEx('panel.display_floor_plan_panel.html_svg_header', 'Floor Plan')} ${Localization().getStringEx('panel.display_floor_plan_panel.html_error', 'No Floor Plan')} ${Localization().getStringEx('panel.display_floor_plan_panel.html_svg_footer', 'Floor Plan')}';
      }
    }
  }

  Future<void> loadFloorPlan(String floorCode) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    Map<String, dynamic>? floorPlanData = await Gateway().fetchFloorPlanData(
      widget.building?.number ?? '',
      floorId: floorCode,
    );

    // Assuming floorPlanSvg contains your SVG string
    String? floorPlanSvg = floorPlanData?['svg'] ?? null;
    String? addButtonsPerAmenity = """
<!DOCTYPE html>
<html>
<head>
  <title>Floor Plan</title>
</head>
<body>
  <!-- Render the SVG -->
  <div id="svg-container">$floorPlanSvg</div>

  <!-- Add buttons dynamically -->
  <script>
    // Get the SVG content from the container
    const svgContainer = document.getElementById("svg-container");
    const floorPlanSvg = svgContainer.innerHTML; // Extract SVG content

    // Parse the SVG string into a DOM object
    const parser = new DOMParser();
    const svgDoc = parser.parseFromString(floorPlanSvg, "image/svg+xml");

    // Get all <g> elements
    const gElements = svgDoc.querySelectorAll("g");

    // Create a Set to store unique aria-labels
    const uniqueAriaLabels = new Set();

    // Map aria-labels to icon URLs
    const iconMap = new Map();

    // Find all patterns and map them to aria-labels
    const patterns = svgDoc.querySelectorAll("pattern");
    patterns.forEach((pattern) => {
      const image = pattern.querySelector("image");
      if (image) {
        const href = image.getAttribute("xlink:href");
        const parentGroup = pattern.closest("g[aria-label]");
        if (parentGroup) {
          const ariaLabel = parentGroup.getAttribute("aria-label");
          iconMap.set(ariaLabel, href);
        }
      }
    });

    // Iterate through <g> elements and collect unique aria-labels
    gElements.forEach((g) => {
      if (!g.hasAttribute("visibility")) {
        g.setAttribute("visibility", "visible");
      }

      const ariaLabel = g.getAttribute("aria-label");
      if (ariaLabel) {
        uniqueAriaLabels.add(ariaLabel);
      }
    });

    // Create a container for buttons
    const buttonsContainer = document.createElement("div");
    buttonsContainer.classList.add("buttons-container");

    uniqueAriaLabels.forEach((label) => {
      const button = document.createElement("button");
      button.classList.add("icon-button"); // Add a class for styling
      button.setAttribute("data-aria-label", label);

      // Add an icon dynamically (if available)
      if (iconMap.has(label)) {
        const iconUrl = iconMap.get(label);
        const iconImg = document.createElement("img");
        iconImg.src = iconUrl;
        iconImg.alt = label;
        iconImg.classList.add("button-icon");
        button.appendChild(iconImg);
      }

      // Add text label for accessibility
      const textNode = document.createTextNode(` \${label}`);
      button.appendChild(textNode);

      // Add click event listener to toggle visibility and change color
      button.addEventListener("click", () => {
        gElements.forEach((g) => {
          if (g.getAttribute("aria-label") === label) {
            const currentVisibility = g.getAttribute("visibility");
            const newVisibility =
              currentVisibility === "visible" ? "hidden" : "visible";
            g.setAttribute("visibility", newVisibility);

            const childElements = g.querySelectorAll("*");
            childElements.forEach((child) => {
              child.setAttribute("visibility", newVisibility);
            });
          }
        });

        button.style.backgroundColor =
          button.style.backgroundColor === "green" ? "" : "green";

        const serializer = new XMLSerializer();
        const updatedFloorPlanSvg = serializer.serializeToString(svgDoc);

        const svgElement = document.querySelector("#svg-container svg");
        if (svgElement) {
          svgElement.outerHTML = updatedFloorPlanSvg;
        }
      });

      buttonsContainer.appendChild(button);
    });

    document.body.appendChild(buttonsContainer);
  </script>

  <!-- Add CSS -->
  <style>
    /* Style for buttons container */
    .buttons-container {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 10px;
      padding: 20px;
      max-width: 800px;
      margin: auto;
    }

    /* Style for individual buttons */
    .icon-button {
      display: flex;
      align-items: center;
      justify-content: flex-start;
      padding: 10px 15px;
      border: none;
      cursor: pointer;
      font-size: 14px;
      background-color: #f0f0f0;
      transition: background-color 0.3s ease, transform 0.2s ease;
      border-radius: 5px;
      box-shadow: 0px 2px 4px rgba(0, 0, 0, 0.1);
    }

    .icon-button:hover {
      background-color: #e0e0e0; /* Hover effect */
      transform: scale(1.02); /* Slight zoom on hover */
    }

    .icon-button img.button-icon {
      width: 30px;
      height: auto;
      margin-right: 10px; /* Space between icon and text */
    }

    .icon-button:active {
      background-color: #d0d0d0; /* Active state */
    }
  </style>
</body>



</html>
""";
    debugPrint(addButtonsPerAmenity);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (floorPlanSvg == null) {
        _htmlWithFloorPlan = '${Localization().getStringEx('panel.display_floor_plan_panel.html_svg_header', 'Floor Plan')} ${Localization().getStringEx('panel.display_floor_plan_panel.html_error', 'No Floor Plan')} ${Localization().getStringEx('panel.display_floor_plan_panel.html_svg_footer', 'Floor Plan')}';
      } else {
        _htmlWithFloorPlan = '$addButtonsPerAmenity ${Localization().getStringEx('panel.display_floor_plan_panel.html_svg_footer', 'Floor Plan')}';
      }
      _controller.loadHtmlString(_htmlWithFloorPlan);
    });
  }

  void changeActiveFloor(String? floorCode) {
    if (floorCode != null) {
      loadFloorPlan(floorCode);
      if (!mounted) return;
      setState(() {
        _currentFloorCode = floorCode;
      });
    }
  }


  void viewNextFloor(int direction) {
    List<String>? floors = widget.building?.floors;
    if (floors != null && floors.isNotEmpty) {
      int currentIndex = floors.indexOf(_currentFloorCode);
      int newIndex = (currentIndex + direction).clamp(0, floors.length - 1);

      if (newIndex != currentIndex) {
        changeActiveFloor(floors[newIndex]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HeaderBar(title: ' ${widget.building?.name ?? ''}'),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(),
            ),
          buildFooter(),
        ],
      ),
    );
  }

  Widget buildFooter() {
    List<String>? floors = widget.building?.floors;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Semantics(
        child: Container(
          color: Styles().colors.textColorPrimary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.all(10.0),
                child: GestureDetector(
                  onTap: () => viewNextFloor(-1),
                  child: floors != null
                      ? Styles().images.getImage('chevron-left-bold') ?? Container()
                      : Container(
                    foregroundDecoration: BoxDecoration(
                      color: Styles().colors.mediumGray,
                      backgroundBlendMode: BlendMode.saturation,
                    ),
                    child: Styles().images.getImage('chevron-left-bold') ?? Container(),
                  ),
                ),
              ),
              Flexible(child: FractionallySizedBox(widthFactor: 0.5)),
              if (floors != null)
                Semantics(
                  container: true,
                  button: true,
                  child: buildAccountDropDown(
                    '${Localization().getStringEx('panel.display_floor_plan_panel.footer.menu_item', 'Floor')} $_currentFloorCode',
                  ),
                ),
              Flexible(child: FractionallySizedBox(widthFactor: 0.5)),
              Padding(
                padding: EdgeInsets.all(10.0),
                child: GestureDetector(
                  onTap: () => viewNextFloor(1),
                  child: floors != null
                      ? Styles().images.getImage('chevron-right-bold') ?? Container()
                      : Container(
                    foregroundDecoration: BoxDecoration(
                      color: Styles().colors.mediumGray,
                      backgroundBlendMode: BlendMode.saturation,
                    ),
                    child: Styles().images.getImage('chevron-right-bold') ?? Container(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> buildDropDownItems() {
    List<String>? floors = widget.building?.floors;
    return floors?.map((floorLetters) {
      return DropdownMenuItem<String>(
        value: floorLetters,
        child: Semantics(
          label:
          '${Localization().getStringEx('panel.display_floor_plan_panel.footer.menu_item', 'Floor')} $floorLetters',
          hint:
          '${Localization().getStringEx('panel.display_floor_plan_panel.footer.hint', 'Double tap to select floor')}',
          button: false,
          excludeSemantics: true,
          child: Center(
            child: Text(
              '${Localization().getStringEx('panel.display_floor_plan_panel.footer.menu_item', 'Floor')} $floorLetters',
              style:
              Styles().textStyles.getTextStyle("widget.button.title.medium"),
            ),
          ),
        ),
      );
    }).toList() ??
        [];
  }

  Widget buildAccountDropDown(String currentFloor) {
    return Semantics(
      label: currentFloor,
      hint:
      '${Localization().getStringEx('panel.display_floor_plan_panel.footer.hint', 'Double tap to select floor')}',
      button: true,
      container: true,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          icon: Padding(
            padding: EdgeInsets.only(left: 4),
            child:
            Styles().images.getImage('chevron-down-dark-blue', excludeFromSemantics: true),
          ),
          isExpanded: false,
          style:
          Styles().textStyles.getTextStyle('widget.title.regular.fat'),
          hint: Text(
            currentFloor,
            style:
            Styles().textStyles.getTextStyle('widget.title.regular.fat'),
          ),
          dropdownColor:
          Styles().colors.white, // Dropdown menu background
          items: buildDropDownItems(),
          onChanged: changeActiveFloor,
        ),
      ),
    );
  }
}


