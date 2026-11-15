(() => {
  let validationSlotId = 0;
  const submittingButtons = new WeakMap();
  const pendingInvalidFocus = new WeakSet();

  function isFormControl(control) {
    return control instanceof HTMLInputElement ||
      control instanceof HTMLSelectElement ||
      control instanceof HTMLTextAreaElement;
  }

  function addDismissButton(notice) {
    if (notice.querySelector("[data-dismiss-message]")) return;
    const content = document.createElement("span");
    content.className = "flash-content";
    while (notice.firstChild) content.append(notice.firstChild);
    const dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.className = "flash-dismiss";
    dismiss.dataset.dismissMessage = "true";
    dismiss.setAttribute("aria-label", "Dismiss message");
    dismiss.textContent = "×";
    notice.append(content, dismiss);
  }

  function prepareFormValidation(form) {
    form.querySelectorAll(".form-field").forEach((field) => {
      const control = field.querySelector(
        'input:not([type="hidden"]):not([type="submit"]), select, textarea',
      );
      if (!control || control.disabled) return;
      let slot = field.querySelector(".field-error-slot");
      if (!slot) {
        slot = document.createElement("span");
        slot.className = "field-error-slot";
        slot.id = `ramp-field-error-${++validationSlotId}`;
        slot.setAttribute("aria-live", "polite");
        field.append(slot);
      }
      const descriptions = new Set(
        (control.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean),
      );
      descriptions.add(slot.id);
      control.setAttribute("aria-describedby", [...descriptions].join(" "));
    });
  }

  function updateFieldValidation(control) {
    const field = control.closest(".form-field");
    const slot = field?.querySelector(".field-error-slot");
    if (!slot) return;
    if (control.validity.valid) {
      slot.textContent = "";
      slot.removeAttribute("title");
      control.removeAttribute("aria-invalid");
      return;
    }
    control.dataset.validationShown = "true";
    control.setAttribute("aria-invalid", "true");
    const message = control.validationMessage || "Check this field and try again.";
    slot.textContent = message;
    slot.title = message;
  }

  function setSubmitting(form, isSubmitting, submitter = null) {
    const button = submitter instanceof HTMLButtonElement
      ? submitter
      : submittingButtons.get(form) || form.querySelector('button[type="submit"], button:not([type])');
    if (!button) return;
    if (isSubmitting) {
      if (button.dataset.submitLoading === "true") return;
      submittingButtons.set(form, button);
      button.dataset.submitLoading = "true";
      button.dataset.submitPreviousDisabled = String(button.disabled);
      button.dataset.submitPreviousWidth = button.style.width;
      button.dataset.submitHadAriaLabel = String(button.hasAttribute("aria-label"));
      button.dataset.submitPreviousAriaLabel = button.getAttribute("aria-label") || "";
      button.style.width = `${button.getBoundingClientRect().width}px`;
      button.disabled = true;
      button.classList.add("is-loading");
      button.setAttribute("aria-label", form.dataset.loadingLabel || button.textContent.trim());
      const spinner = document.createElement("span");
      spinner.className = "submit-spinner";
      spinner.setAttribute("aria-hidden", "true");
      button.prepend(spinner);
      return;
    }
    if (button.dataset.submitLoading !== "true") return;
    button.querySelector(".submit-spinner")?.remove();
    button.classList.remove("is-loading");
    button.style.width = button.dataset.submitPreviousWidth || "";
    button.disabled = button.dataset.submitPreviousDisabled === "true";
    if (button.dataset.submitHadAriaLabel === "true") {
      button.setAttribute("aria-label", button.dataset.submitPreviousAriaLabel || "");
    } else {
      button.removeAttribute("aria-label");
    }
    delete button.dataset.submitLoading;
    delete button.dataset.submitPreviousDisabled;
    delete button.dataset.submitPreviousWidth;
    delete button.dataset.submitHadAriaLabel;
    delete button.dataset.submitPreviousAriaLabel;
    submittingButtons.delete(form);
  }

  function showFormError(form, message) {
    const error = document.createElement("p");
    error.className = "form-error";
    error.setAttribute("role", "alert");
    error.textContent = message;
    form.querySelector(".form-error")?.remove();
    addDismissButton(error);
    form.prepend(error);
  }

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("form").forEach(prepareFormValidation);
    const formErrorTarget = document.querySelector("form.landlord-form, form.login-form");
    document.querySelectorAll(".flash-error").forEach((notice) => {
      notice.setAttribute("role", "alert");
      addDismissButton(notice);
      if (formErrorTarget) {
        notice.classList.add("form-error");
        formErrorTarget.prepend(notice);
      }
    });
    document.querySelectorAll(".flash").forEach(addDismissButton);
    document.querySelectorAll(".form-error").forEach(addDismissButton);

    document.addEventListener("focusout", (event) => {
      const control = event.target;
      if (!isFormControl(control) || !control.closest(".form-field")) return;
      if (control.validity.valid) {
        if (control.dataset.validationShown === "true") updateFieldValidation(control);
        return;
      }
      control.dataset.validationShown = "true";
      updateFieldValidation(control);
    });

    const validateShownField = (event) => {
      const control = event.target;
      if (isFormControl(control) && control.dataset.validationShown === "true") {
        updateFieldValidation(control);
      }
    };
    document.addEventListener("input", validateShownField);
    document.addEventListener("change", validateShownField);
    document.addEventListener("invalid", (event) => {
      const control = event.target;
      if (!isFormControl(control) || !control.closest(".form-field")) return;
      event.preventDefault();
      control.dataset.validationShown = "true";
      updateFieldValidation(control);
      const form = control.form;
      if (!form || pendingInvalidFocus.has(form)) return;
      pendingInvalidFocus.add(form);
      window.requestAnimationFrame(() => {
        pendingInvalidFocus.delete(form);
        const firstInvalid = [...form.querySelectorAll(
          '.form-field input:not([type="hidden"]):not([type="submit"]), .form-field select, .form-field textarea',
        )].find((field) => !field.disabled && !field.validity.valid);
        if (!firstInvalid) return;
        firstInvalid.focus({ preventScroll: true });
        firstInvalid.scrollIntoView({
          block: "center",
          behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
        });
      });
    }, true);

    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const dismiss = event.target.closest("[data-dismiss-message]");
      if (!dismiss) return;
      const notice = dismiss.closest(".flash, .form-error");
      if (!notice) return;
      notice.classList.add("flash-dismissed");
      window.setTimeout(() => notice.remove(), 180);
    });

    document.querySelectorAll(".flash-success").forEach((notice) => {
      window.setTimeout(() => {
        notice.classList.add("flash-dismissed");
        window.setTimeout(() => notice.remove(), 180);
      }, 4000);
    });
  });

  window.addEventListener("pageshow", () => {
    document.querySelectorAll('form[aria-busy="true"]').forEach((form) => {
      form.removeAttribute("aria-busy");
      setSubmitting(form, false);
    });
  });

  window.rampFormUX = {
    addDismissButton,
    prepareFormValidation,
    setSubmitting,
    showFormError,
  };
})();
