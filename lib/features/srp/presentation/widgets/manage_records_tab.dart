import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/create_srp_request.dart';
import '../../data/providers/srp_providers.dart';

/// Manage Records tab — form to encode a new SRP record.
///
/// Sends a [CreateSrpRequest] to the server via [SrpList.createSrp].
/// Fields:
/// - Price per KG (PHP)
/// - Reference number
/// - Date Effective (date + time pickers)
/// - End Date / Time (optional)
class ManageRecordsTab extends ConsumerStatefulWidget {
  const ManageRecordsTab({super.key});

  @override
  ConsumerState<ManageRecordsTab> createState() => _ManageRecordsTabState();
}

class _ManageRecordsTabState extends ConsumerState<ManageRecordsTab> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _referenceController = TextEditingController();

  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();

  DateTime? _endDate;
  TimeOfDay? _endTime;

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  // ── Computed fields ─────────────────────────────────────────────────────────

  DateTime get _startDateTime => DateTime(
    _startDate.year,
    _startDate.month,
    _startDate.day,
    _startTime.hour,
    _startTime.minute,
  ).toUtc();

  DateTime? get _endDateTime {
    if (_endDate == null) return null;
    final t = _endTime ?? const TimeOfDay(hour: 23, minute: 59);
    return DateTime(
      _endDate!.year,
      _endDate!.month,
      _endDate!.day,
      t.hour,
      t.minute,
    ).toUtc();
  }

  // ── Pickers ─────────────────────────────────────────────────────────────────

  Future<void> _pickDate({required bool isEnd}) async {
    final now = DateTime.now();
    final initial = isEnd ? (_endDate ?? now) : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primaryRed),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isEnd) {
        _endDate = picked;
      } else {
        _startDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final initial = isEnd
        ? (_endTime ?? const TimeOfDay(hour: 23, minute: 59))
        : _startTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primaryRed),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isEnd) {
        _endTime = picked;
      } else {
        _startTime = picked;
      }
    });
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final price = double.parse(_priceController.text.trim());
    final request = CreateSrpRequest(
      price: price,
      reference: _referenceController.text.trim(),
      startDate: _startDateTime,
      endDate: _endDateTime,
    );

    final result = await ref.read(srpListProvider.notifier).createSrp(request);

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (result != null) {
        _successMessage =
            'SRP record (PHP ${price.toStringAsFixed(0)}/kg) created successfully!';
        _priceController.clear();
        _referenceController.clear();
        _startDate = DateTime.now();
        _startTime = TimeOfDay.now();
        _endDate = null;
        _endTime = null;
      } else {
        _errorMessage =
            'Failed to create SRP record. Check your connection and try again.';
      }
    });
  }

  @override
  void dispose() {
    _priceController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 3,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Card header ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              color: AppTheme.primaryRed,
              child: const Text(
                'ENCODE SRP RECORD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // ── Form body ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price / KG
                    _FieldLabel('Price per KG (PHP)'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _priceController,
                      style: const TextStyle(color: Colors.black87),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        prefixText: 'PHP  ',
                        hintText: '0.00',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Price is required';
                        final parsed = double.tryParse(v);
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid price greater than 0';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    // Reference number
                    _FieldLabel('Reference No.'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _referenceController,
                      style: const TextStyle(color: Colors.black87),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'e.g. DA-MO-2026-001',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Reference number is required';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    // Date Effective
                    _FieldLabel('Date Effective'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _PickerButton(
                            label: dateFormat.format(_startDate),
                            icon: Icons.calendar_today_outlined,
                            onTap: () => _pickDate(isEnd: false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PickerButton(
                            label: _startTime.format(context),
                            icon: Icons.access_time_outlined,
                            onTap: () => _pickTime(isEnd: false),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // End Date (optional)
                    _FieldLabel('End Date  (optional)'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _PickerButton(
                            label: _endDate != null
                                ? dateFormat.format(_endDate!)
                                : 'No end date',
                            icon: Icons.event_outlined,
                            onTap: () => _pickDate(isEnd: true),
                            muted: _endDate == null,
                          ),
                        ),
                        if (_endDate != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PickerButton(
                              label: _endTime != null
                                  ? _endTime!.format(context)
                                  : '11:59 PM',
                              icon: Icons.access_time_outlined,
                              onTap: () => _pickTime(isEnd: true),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _endDate = null;
                              _endTime = null;
                            }),
                            icon: const Icon(Icons.close),
                            color: AppTheme.primaryRed,
                            tooltip: 'Clear end date',
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Feedback messages ──────────────────────────────────
                    if (_errorMessage != null) ...[
                      _FeedbackBanner(message: _errorMessage!, isError: true),
                      const SizedBox(height: 12),
                    ],

                    if (_successMessage != null) ...[
                      _FeedbackBanner(
                        message: _successMessage!,
                        isError: false,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Submit button ──────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.primaryRed
                              .withAlpha(120),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'UPDATE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 1.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: Colors.black87,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppTheme.primaryRed;
    final borderColor = muted
        ? const Color(0xFFCCC0B0)
        : activeColor.withAlpha(160);
    final iconColor = muted ? Colors.grey.shade500 : activeColor;
    final textColor = muted ? Colors.grey.shade500 : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bgColor = isError ? Colors.red.shade50 : Colors.green.shade50;
    final borderColor = isError ? Colors.red.shade200 : Colors.green.shade200;
    final iconColor = isError ? Colors.red.shade600 : Colors.green.shade600;
    final textColor = isError ? Colors.red.shade800 : Colors.green.shade800;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
