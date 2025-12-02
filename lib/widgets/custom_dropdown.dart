import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Modern minimalist dropdown with smooth animations
/// Features: Clean styling, subtle shadows, animated focus state
class CustomDropdown<T> extends StatefulWidget {
  final String label;
  final String? hint;
  final List<Map<String, dynamic>> items;
  final T? selectedValue;
  final Function(T?) onChanged;
  final bool isRequired;
  final IconData? prefixIcon;

  const CustomDropdown({
    super.key,
    required this.label,
    this.hint,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
    this.isRequired = false,
    this.prefixIcon,
  });

  @override
  State<CustomDropdown<T>> createState() => _CustomDropdownState<T>();
}

class _CustomDropdownState<T> extends State<CustomDropdown<T>> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _isFocused ? AppColors.primary : AppColors.neutral700,
                  letterSpacing: -0.2,
                ),
              ),
              if (widget.isRequired) ...[
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Dropdown Container
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused 
                  ? AppColors.primary 
                  : AppColors.neutral300,
              width: _isFocused ? 1.5 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppColors.neutral900.withValues(alpha: 0.04),
                      blurRadius: 4,
                      spreadRadius: 0,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Focus(
            focusNode: _focusNode,
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<T>(
                  value: widget.selectedValue,
                  isExpanded: true,
                  hint: widget.hint != null
                      ? Text(
                          widget.hint!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: AppColors.neutral500,
                          ),
                        )
                      : null,
                  icon: AnimatedRotation(
                    turns: _isFocused ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _isFocused 
                          ? AppColors.primary 
                          : AppColors.neutral500,
                      size: 24,
                    ),
                  ),
                  padding: EdgeInsets.only(
                    left: widget.prefixIcon != null ? 8 : 16,
                    right: 12,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: AppColors.white,
                  elevation: 4,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.neutral900,
                  ),
                  selectedItemBuilder: widget.prefixIcon != null
                      ? (context) => widget.items.map((item) {
                            return Row(
                              children: [
                                Icon(
                                  widget.prefixIcon,
                                  size: 20,
                                  color: AppColors.neutral500,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item['label'],
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.neutral900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          }).toList()
                      : null,
                  items: widget.items.map((item) {
                    final isSelected = item['value'] == widget.selectedValue;
                    return DropdownMenuItem<T>(
                      value: item['value'] as T,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primarySurface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            if (isSelected) ...[
                              Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                item['label'],
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.neutral900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    widget.onChanged(value);
                    _focusNode.unfocus();
                  },
                  onTap: () => _focusNode.requestFocus(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
